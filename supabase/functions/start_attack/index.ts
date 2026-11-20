// start_attack (#166, #25): start ataku po stronie serwera. Id atakującego idzie wyłącznie z tokenu.
// Całą walidację i zapis robi `public.begin_attack` w jednej transakcji (migracje *_finish_attack.sql
// i *_army_limits.sql): limit 10 startów na 10 minut, armia nie większa niż w zamku atakującego
// i w jego limicie miejsc oraz utrzymania żywności (#249), cel bez tarczy, w zasięgu epoki
// i rankingu, nieatakowany przez niego w 24 h i bez innego ataku w toku (blokada celu).
// Odpowiedź: id ataku, seed terenu obrońcy (`map_seed`) osobno od seeda bitwy (`battle_seed`) i przy
// ataku na gracza kopie jego zamku i obrony, z których klient liczy bitwę.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["defender_id", "bot_idx", "army"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// błędy z begin_attack (raise exception ... P0001) → kod HTTP
const ERRORS: Record<string, number> = {
  rate_limited: 429,
  target_busy: 409,
  target_shielded: 409,
  target_recent: 409,
  target_out_of_range: 409,
  attacker_no_castle: 409,
  army_over_limit: 409,
  army_over_upkeep: 409,
  target_not_found: 404,
  attacker_not_found: 404,
  army_not_owned: 400,
  bad_army: 400,
  bad_target: 400,
  self_attack: 400,
  bad_seed: 500,
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  const auth = req.headers.get("Authorization") ?? "";
  if (!auth.startsWith("Bearer ")) {
    return json({ error: "unauthorized" }, 401);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!supabaseUrl || !anonKey || !serviceKey) {
    return json({ error: "misconfigured" }, 500);
  }

  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: auth } },
  });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json({ error: "unauthorized" }, 401);
  }
  const attackerId = userData.user.id;

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (typeof body !== "object" || body === null || Array.isArray(body)) {
    return json({ error: "invalid_body" }, 400);
  }
  const b = body as Record<string, unknown>;
  if (Object.keys(b).some((k) => !ALLOWED_KEYS.has(k))) {
    return json({ error: "unknown_field" }, 400);
  }

  const defenderId = typeof b.defender_id === "string" ? b.defender_id : null;
  const botIdx = typeof b.bot_idx === "number" && Number.isInteger(b.bot_idx) ? b.bot_idx : null;
  if ((defenderId == null) === (botIdx == null)) {
    return json({ error: "target_required" }, 400);
  }
  if (defenderId != null && !UUID.test(defenderId)) {
    return json({ error: "bad_target" }, 400);
  }
  if (botIdx != null && (botIdx < 0 || botIdx > 19)) {
    return json({ error: "bad_bot" }, 400);
  }
  // kształt i zakresy armii sprawdza begin_attack; tu tylko rozmiar żądania
  if (!Array.isArray(b.army) || b.army.length < 1 || b.army.length > 16) {
    return json({ error: "bad_army" }, 400);
  }

  // seed bitwy z kryptograficznego źródła; osobny od map_seed
  const battleSeed = crypto.getRandomValues(new Uint32Array(1))[0]! & 0x7fffffff;

  const admin = createClient(supabaseUrl, serviceKey);
  const { data, error } = await admin.rpc("begin_attack", {
    p_attacker: attackerId,
    p_defender: defenderId,
    p_bot: botIdx,
    p_army: b.army,
    p_battle_seed: battleSeed,
  });
  if (error) {
    const code = known(error);
    if (code) {
      return json({ error: code }, ERRORS[code]!);
    }
    console.error("start_attack rpc", error.code);
    return json({ error: "start_failed" }, 500);
  }
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return json({ error: "start_failed" }, 500);
  }

  // bez kluczy null: klient z has()/filtrami typu nie dostaje fałszywego bot_idx: 0
  const payload: Record<string, unknown> = {
    id: row.attack_id,
    map_seed: row.map_seed,
    battle_seed: row.battle_seed,
  };
  if (defenderId != null) {
    payload.defender_id = defenderId;
    payload.castle = row.castle ?? {};
    payload.defense = row.defense ?? {};
  } else {
    payload.bot_idx = botIdx;
  }
  return json(payload);
});

// Kod błędu z `raise exception '<kod>'`; PostgREST może dodać prefiks albo przenieść treść do details.
function known(error: { code?: string; message?: string; details?: string }): string | null {
  if (error.code !== "P0001") {
    return null;
  }
  const text = `${error.message ?? ""} ${error.details ?? ""}`;
  for (const code of Object.keys(ERRORS)) {
    if (new RegExp(`\\b${code}\\b`).test(text)) {
      return code;
    }
  }
  return null;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

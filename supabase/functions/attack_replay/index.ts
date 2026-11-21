// attack_replay (#29): dane do powtórki zakończonej obrony. Id gracza idzie wyłącznie z tokenu, a
// `public.attack_replay` oddaje je tylko obrońcy: seedy, kopie zamku i obrony z chwili startu, armię,
// plan, badania i generała (#31) atakującego zapisane przy zatwierdzeniu planu. Obrońca liczy z nich bitwę jeszcze raz
// (powtórka to nie wideo), więc widzi ten sam przebieg co atakujący. Bez danych atakującego poza armią
// i planem (kto atakował, gra tu nie potrzebuje).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["attack_id"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ERRORS: Record<string, number> = {
  attack_not_found: 404,
  // atak sprzed #29: bez zapisanego planu nie ma z czego liczyć
  replay_missing: 410,
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
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: auth } } });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json({ error: "unauthorized" }, 401);
  }

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
  const attackId = typeof b.attack_id === "string" ? b.attack_id : "";
  if (!UUID.test(attackId)) {
    return json({ error: "bad_attack" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const { data, error } = await admin.rpc("attack_replay", { p_player: userData.user.id, p_attack: attackId });
  if (error) {
    const code = known(error);
    if (code) {
      return json({ error: code }, ERRORS[code]!);
    }
    console.error("attack_replay rpc", error.code);
    return json({ error: "replay_failed" }, 500);
  }
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return json({ error: "replay_failed" }, 500);
  }
  return json({
    id: attackId,
    map_seed: row.map_seed,
    battle_seed: row.battle_seed,
    castle: row.castle ?? {},
    defense: row.defense ?? {},
    army: row.army ?? [],
    plan: row.plan ?? [],
    techs: row.techs ?? [],
    general: row.general ?? null,
    result: row.result ?? {},
    loot: row.loot ?? [0, 0, 0, 0],
    finished_at: row.finished_at,
  });
});

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
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

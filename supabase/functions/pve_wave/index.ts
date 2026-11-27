// pve_wave (#288): fala PvE przez serwer. Id gracza idzie wyłącznie z tokenu. Dwa rodzaje żądania:
// - start: `{"wave": n}` woła `public.begin_wave` (fala od postępu serwera w górę, jedna naraz,
//   10 startów na 10 minut) i zwraca `{id, wave}`;
// - koniec: `{"wave_id": id, "won": true|false}` woła `public.end_wave` (wygrana najwcześniej 5 sekund
//   po starcie, wynik najpóźniej 10 minut po nim) i zwraca `{status, wave, reward}`.
// Nagrodę za wygraną falę dopisuje serwer do zamku (`castle_loot_pending`, migracja *_pve_wave_results.sql);
// telefon dolicza ją z odpowiedzi na najbliższy zapis zamku (`loot_applied`). Ponowienie końca zwraca
// zapisany wynik bez drugiej nagrody.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["wave", "wave_id", "won"]);
// PveWaves.COUNT w grze
const WAVES = 5;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// błędy z begin_wave / end_wave (raise exception ... P0001) → kod HTTP
const ERRORS: Record<string, number> = {
  rate_limited: 429,
  wave_done: 409,
  no_castle: 409,
  wave_too_fast: 422,
  player_not_found: 404,
  wave_not_found: 404,
  bad_wave: 400,
  bad_result: 400,
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
  const playerId = userData.user.id;

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

  const admin = createClient(supabaseUrl, serviceKey);
  if (await clientOutdated(req, admin)) {
    return json({ error: "update_required" }, 426);
  }
  const start = b.wave !== undefined;
  if (start === (b.wave_id !== undefined) || (start && b.won !== undefined)) {
    return json({ error: "bad_request" }, 400);
  }

  if (start) {
    if (typeof b.wave !== "number" || !Number.isInteger(b.wave) || b.wave < 0 || b.wave >= WAVES) {
      return json({ error: "bad_wave" }, 400);
    }
    const { data, error } = await admin.rpc("begin_wave", { p_player: playerId, p_wave: b.wave });
    if (error) {
      return failure("begin_wave", error);
    }
    const row = Array.isArray(data) ? data[0] : null;
    if (!row) {
      return json({ error: "wave_failed" }, 500);
    }
    return json({ id: row.run_id, wave: row.wave });
  }

  if (typeof b.wave_id !== "string" || !UUID.test(b.wave_id)) {
    return json({ error: "bad_wave" }, 400);
  }
  if (typeof b.won !== "boolean") {
    return json({ error: "bad_result" }, 400);
  }
  const { data, error } = await admin.rpc("end_wave", { p_player: playerId, p_run: b.wave_id, p_won: b.won });
  if (error) {
    return failure("end_wave", error);
  }
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return json({ error: "wave_failed" }, 500);
  }
  if (row.status !== "won" && row.status !== "lost") {
    // fala porzucona (nowy start) albo po terminie: wyniku już się nie przyjmuje
    return json({ error: "wave_expired" }, 410);
  }
  return json({ status: row.status, wave: row.wave, reward: row.reward });
});

function failure(rpc: string, error: { code?: string; message?: string; details?: string }): Response {
  const code = known(error);
  if (code) {
    return json({ error: code }, ERRORS[code]!);
  }
  // sam kod błędu, bez treści żądania (zasada: bez danych graczy w logach)
  console.error(`pve_wave ${rpc}`, error.code);
  return json({ error: "wave_failed" }, 500);
}

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

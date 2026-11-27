// scout (#28): zwiad na gracza. Id atakującego idzie wyłącznie z tokenu. Całą walidację i zapis robi
// `public.begin_scout` (migracja *_scouting.sql): Chata tropicieli, S1 i zwiadowcy z zamku na
// serwerze, cel z tej samej epoki (#383), naraz jedna misja, 30 na dobę. Wynik losuje się z seeda
// z kryptograficznego źródła serwera; odpowiedź podaje tylko koniec misji i ilu zwiadowców poszło.
// Wynik i odsłonięte dane daje `scout_reports` po końcu misji.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["defender_id", "duration"]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// błędy z begin_scout (raise exception ... P0001) → kod HTTP
const ERRORS: Record<string, number> = {
  rate_limited: 429,
  scout_busy: 409,
  no_building: 409,
  no_tech: 409,
  no_scouts: 409,
  attacker_no_castle: 409,
  target_out_of_range: 409,
  target_not_found: 404,
  attacker_not_found: 404,
  self_scout: 400,
  bad_target: 400,
  bad_duration: 400,
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
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: auth } } });
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
  const defenderId = typeof b.defender_id === "string" ? b.defender_id : "";
  if (!UUID.test(defenderId)) {
    return json({ error: "bad_target" }, 400);
  }
  const duration = typeof b.duration === "number" && Number.isInteger(b.duration) ? b.duration : -1;
  if (duration < 0 || duration > 2) {
    return json({ error: "bad_duration" }, 400);
  }

  const seed = crypto.getRandomValues(new Uint32Array(1))[0]! & 0x7fffffff;
  const admin = createClient(supabaseUrl, serviceKey);
  if (await clientOutdated(req, admin)) {
    return json({ error: "update_required" }, 426);
  }
  const { data, error } = await admin.rpc("begin_scout", {
    p_attacker: attackerId,
    p_defender: defenderId,
    p_duration: duration,
    p_seed: seed,
  });
  if (error) {
    const code = known(error);
    if (code) {
      return json({ error: code }, ERRORS[code]!);
    }
    console.error("scout rpc", error.code);
    return json({ error: "scout_failed" }, 500);
  }
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return json({ error: "scout_failed" }, 500);
  }
  // czas do końca w sekundach: klient liczy koniec od swojego zegara, nie od zegara serwera
  const remaining = Math.max(0, Math.ceil((Date.parse(row.ends_at) - Date.now()) / 1000));
  return json({ id: row.mission_id, remaining_s: remaining, trackers: row.trackers, scouts: row.scouts });
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

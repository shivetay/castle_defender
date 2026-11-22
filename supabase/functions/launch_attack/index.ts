// launch_attack (#28): zatwierdzenie planu ataku na gracza. Dopiero teraz klient dostaje pełne kopie
// zamku i obrony obrońcy z chwili startu (bez jego stanu zwiadu), z których liczy bitwę; plan ataku
// widział tylko zarys i to, co odsłonił zwiad. `public.launch_attack` zapisuje chwilę zatwierdzenia,
// a `end_attack` przyjmuje wynik tylko po niej. Ponowienie dla tego samego ataku zwraca to samo.
// #29: żądanie niesie plan ataku (rozkazy oddziałów), który serwer sprawdza i zapisuje do powtórki
// u obrońcy, a odpowiedź oddaje zapisany plan i badania atakującego z jego zamku na serwerze. Klient
// liczy bitwę z nich, więc obrońca w powtórce widzi ten sam przebieg.
// #31: żądanie może nieść rodzaj generała ataku (`general`, liczba 0..2). Poziom i perk serwer bierze
// z zamku atakującego na serwerze (`private.castle_general`) i oddaje w odpowiedzi.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["attack_id", "plan", "general"]);
// Generals.Kind w grze: Wódz drużyny, Łowczy, Budowniczy kopców
const MAX_GENERAL = 2;
// AttackPlan.MAX_SQUADS_BY_AGE[-1] w grze; dokładny limit (liczba oddziałów armii) sprawdza check_plan
const MAX_ORDERS = 8;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const ERRORS: Record<string, number> = {
  attack_not_found: 404,
  attack_expired: 409,
  bad_plan: 400,
  bad_general: 400,
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
  // kształt i zakresy rozkazów sprawdza check_plan w bazie; tu tylko typ i rozmiar żądania
  if (!Array.isArray(b.plan) || b.plan.length < 1 || b.plan.length > MAX_ORDERS) {
    return json({ error: "bad_plan" }, 400);
  }

  let general: number | null = null;
  if (b.general !== undefined) {
    if (typeof b.general !== "number" || !Number.isInteger(b.general) || b.general < 0 || b.general > MAX_GENERAL) {
      return json({ error: "bad_general" }, 400);
    }
    general = b.general;
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const { data, error } = await admin.rpc("launch_attack", {
    p_attacker: userData.user.id,
    p_attack: attackId,
    p_plan: b.plan,
    p_general: general,
  });
  if (error) {
    const code = known(error);
    if (code) {
      return json({ error: code }, ERRORS[code]!);
    }
    console.error("launch_attack rpc", error.code);
    return json({ error: "launch_failed" }, 500);
  }
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return json({ error: "launch_failed" }, 500);
  }
  return json({
    id: attackId,
    castle: row.castle ?? {},
    defense: row.defense ?? {},
    plan: row.plan ?? [],
    techs: row.techs ?? [],
    general: row.general ?? null,
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

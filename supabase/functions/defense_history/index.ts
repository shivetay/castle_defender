// defense_history (#328): historia obron gracza. Id gracza idzie wyłącznie z tokenu, a
// `public.defense_history` oddaje tylko ataki na jego zamek: id ataku, koniec, wynik z serwera, armię
// napastnika z chwili startu (klient liczy z niej wskaźnik siły), czy jest powtórka, nick napastnika
// i dolną granicę przedziału siły obrony jego zamku (#293, mgła: nigdy dokładna liczba; null bez zamku).
// Bez id napastnika i nazwy jego zamku. Treść żądania: {} (pusta). Niczego nie zapisuje.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

// HISTORY_LIMIT = 10
const MAX_ROWS = 10;
const MAX_NICK = 20;

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
  if (typeof body !== "object" || body === null || Array.isArray(body) || Object.keys(body).length > 0) {
    return json({ error: "invalid_body" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  if (await clientOutdated(req, admin)) {
    return json({ error: "update_required" }, 426);
  }
  const { data, error } = await admin.rpc("defense_history", { p_player: userData.user.id });
  if (error || !Array.isArray(data)) {
    console.error("defense_history rpc", error?.code);
    return json({ error: "history_failed" }, 500);
  }
  const rows = data.slice(0, MAX_ROWS).map((row: Record<string, unknown>) => ({
    id: String(row.id ?? ""),
    finished_at: String(row.finished_at ?? ""),
    result: row.result ?? {},
    army: Array.isArray(row.attacker_army) ? row.attacker_army : [],
    has_replay: row.has_replay === true,
    nickname: typeof row.nickname === "string" ? row.nickname.slice(0, MAX_NICK) : "",
    defense: Number.isInteger(row.defense) ? row.defense : null,
  }));
  return json({ rows });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

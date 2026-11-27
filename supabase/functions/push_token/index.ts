// push_token (#30, ADR 0012): zapis albo usunięcie tokenu FCM urządzenia gracza. Id gracza idzie wyłącznie
// z tokenu JWT, nigdy z treści. Klient nie ma uprawnień do `public.push_tokens`, więc to jedyna droga zapisu.
// Treść: {"token": "<token FCM>", "attacks": true|false} zapisuje token z przełącznikiem „Ataki”,
// {"token": "<token FCM>", "remove": true} usuwa własny token (wyłączenie powiadomień na urządzeniu).
// Odpowiedź: {"ok": true}. Token nie trafia do logów ani do odpowiedzi.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

const TOKEN = /^[A-Za-z0-9_:-]{20,512}$/;

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
  const keys = Object.keys(b).sort().join(",");
  const remove = keys === "remove,token" && b.remove === true;
  const register = keys === "attacks,token" && typeof b.attacks === "boolean";
  if (!remove && !register) {
    return json({ error: "invalid_body" }, 400);
  }
  if (typeof b.token !== "string" || !TOKEN.test(b.token)) {
    return json({ error: "bad_token" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  if (await clientOutdated(req, admin)) {
    return json({ error: "update_required" }, 426);
  }
  const { error } = remove
    ? await admin.rpc("push_token_unregister", { p_player: userData.user.id, p_token: b.token })
    : await admin.rpc("push_token_register", { p_player: userData.user.id, p_token: b.token, p_attacks: b.attacks });
  if (error) {
    console.error("push_token rpc", error.code);
    return json({ error: "push_token_failed" }, 500);
  }
  return json({ ok: true });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

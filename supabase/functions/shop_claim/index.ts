// shop_claim (#408): odbiór darmowej oferty sklepu w Targu. Id gracza idzie wyłącznie z tokenu.
// Żądanie `{"offer_id": n}` woła `public.claim_offer` (oferta i grupa widoczne, odnowienie od ostatniego
// odbioru na zegarze serwera, miejsce w magazynie) i zwraca `{offer_id, resource, amount, claimed_at,
// next_available_at}`. Nagrodę dopisuje serwer do zamku (`castle_loot_pending`, migracja *_shop.sql);
// telefon dolicza ją z odpowiedzi na najbliższy zapis zamku (`loot_applied`). Ponowienie przed końcem
// odnowienia kończy się `cooldown` bez drugiej nagrody.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["offer_id"]);

// błędy z claim_offer (raise exception ... P0001) → kod HTTP
const ERRORS: Record<string, number> = {
  cooldown: 409,
  storage_full: 409,
  no_castle: 409,
  offer_unavailable: 404,
  player_not_found: 404,
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
  if (typeof b.offer_id !== "number" || !Number.isSafeInteger(b.offer_id) || b.offer_id < 1) {
    return json({ error: "bad_offer" }, 400);
  }

  const { data, error } = await admin.rpc("claim_offer", { p_player: playerId, p_offer: b.offer_id });
  if (error) {
    return failure(error);
  }
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return json({ error: "claim_failed" }, 500);
  }
  return json({
    offer_id: row.offer_id,
    resource: row.resource,
    amount: row.amount,
    claimed_at: row.claimed_at,
    next_available_at: row.next_available_at,
  });
});

function failure(error: { code?: string; message?: string; details?: string }): Response {
  const code = known(error);
  if (code) {
    return json({ error: code }, ERRORS[code]!);
  }
  // sam kod błędu, bez treści żądania (zasada: bez danych graczy w logach)
  console.error("shop_claim claim_offer", error.code);
  return json({ error: "claim_failed" }, 500);
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

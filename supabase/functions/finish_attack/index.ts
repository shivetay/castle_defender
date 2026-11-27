// finish_attack (#25): koniec ataku. Id atakującego idzie wyłącznie z tokenu, a całą walidację i zapis
// robi `public.end_attack` (migracja *_finish_attack.sql): tylko własny atak w toku, w 10 minut od
// startu; wynik zgodny z gwiazdkami; łup nie większy niż niechroniona część zapasów obrońcy z kopii
// z chwili startu i nie większy niż capacity ocalałych jednostek; tarcza obrońcy 8 h od 30 procent.
// Zawyżony wynik albo łup jest odrzucany. Ponowienie dla zakończonego ataku zwraca zapisany wynik.
// Potem zapisuje zniszczone budynki obrońcy (#99, `public.record_destroyed`, migracja *_attack_ruins.sql),
// z których obrońca odbudowuje zamek. Odrzucona lista nie cofa wyniku: obrońca ma wtedy po prostu mniej ruin.
// Na końcu, w tle, push do obrońcy (#30, `_shared/fcm.ts`): raz na atak, błąd FCM nie zmienia odpowiedzi.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";
import { notifyDefender } from "../_shared/fcm.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["attack_id", "result", "loot", "survivors", "destroyed"]);
// AttackFinish.MAX_DESTROYED w grze
const MAX_DESTROYED = 200;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// błędy z end_attack (raise exception ... P0001) → kod HTTP
const ERRORS: Record<string, number> = {
  attack_not_found: 404,
  bad_result: 400,
  bad_survivors: 400,
  bad_loot: 400,
  loot_too_high: 422,
  // #28: wynik ataku na gracza tylko po zatwierdzeniu planu (launch_attack)
  not_launched: 409,
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
  if (typeof b.attack_id !== "string" || !UUID.test(b.attack_id)) {
    return json({ error: "bad_attack" }, 400);
  }
  // kształt i zakresy sprawdza end_attack; tu tylko typy i rozmiar żądania
  if (typeof b.result !== "object" || b.result === null || Array.isArray(b.result)) {
    return json({ error: "bad_result" }, 400);
  }
  if (!Array.isArray(b.loot) || b.loot.length !== 4) {
    return json({ error: "bad_loot" }, 400);
  }
  if (!Array.isArray(b.survivors) || b.survivors.length > 16) {
    return json({ error: "bad_survivors" }, 400);
  }
  // starszy klient nie wysyła listy; wtedy obrońca nie ma ruin
  if (b.destroyed !== undefined && (!Array.isArray(b.destroyed) || b.destroyed.length > MAX_DESTROYED ||
      !b.destroyed.every((v) => Number.isInteger(v)))) {
    return json({ error: "bad_destroyed" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  if (await clientOutdated(req, admin)) {
    return json({ error: "update_required" }, 426);
  }
  const { data, error } = await admin.rpc("end_attack", {
    p_attacker: userData.user.id,
    p_attack: b.attack_id,
    p_result: b.result,
    p_loot: b.loot,
    p_survivors: b.survivors,
  });
  if (error) {
    const code = known(error);
    if (code) {
      return json({ error: code }, ERRORS[code]!);
    }
    console.error("finish_attack rpc", error.code);
    return json({ error: "finish_failed" }, 500);
  }
  const row = Array.isArray(data) ? data[0] : null;
  if (!row) {
    return json({ error: "finish_failed" }, 500);
  }
  if (row.status !== "finished") {
    // atak porzucony albo wygasły (10 minut od startu): wyniku już się nie przyjmuje
    return json({ error: "attack_expired" }, 410);
  }
  if (b.destroyed !== undefined) {
    const { error: ruinErr } = await admin.rpc("record_destroyed", {
      p_attacker: userData.user.id,
      p_attack: b.attack_id,
      p_destroyed: b.destroyed,
    });
    if (ruinErr) {
      // sam kod błędu, bez treści żądania (zasada: bez danych graczy w logach)
      console.error("record_destroyed rpc", ruinErr.code);
    }
  }
  // push o ataku w tle, po odpowiedzi; atak na bota i ponowienie nic nie wysyłają (attack_push_claim)
  EdgeRuntime.waitUntil(notifyDefender(admin, userData.user.id, String(b.attack_id)));
  // bez czasu tarczy obrońcy: atakujący go nie potrzebuje
  return json({ status: row.status, result: row.result, loot: row.loot });
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

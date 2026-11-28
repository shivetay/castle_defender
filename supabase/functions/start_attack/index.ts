// start_attack (#166, #25): start ataku po stronie serwera. Id atakującego idzie wyłącznie z tokenu.
// Całą walidację i zapis robi `public.begin_attack` w jednej transakcji (migracje *_finish_attack.sql
// i *_army_limits.sql): limit 10 startów na 10 minut, armia nie większa niż w zamku atakującego
// i w jego limicie miejsc oraz utrzymania żywności (#249), cel bez tarczy, z tej samej epoki (#383)
// i rankingu, nieatakowany przez niego w 24 h i bez innego ataku w toku (blokada celu).
// Odpowiedź: id ataku, seed terenu obrońcy (`map_seed`) osobno od seeda bitwy (`battle_seed`). Przy
// ataku na gracza (#28, pełne ukrycie obrony) tylko zarys budynków, donżon i to, co odsłonił ostatni
// udany zwiad (`public.attack_preview`); pełne kopie zamku i obrony daje dopiero `launch_attack`.
// Zamek-bot tylko odblokowany w kampanii (#386, ADR 0015): przy odmowie `bot_locked` odpowiedź niesie
// postęp z serwera (`bots_beaten`), żeby telefon wyrównał swój licznik.
// #413 (ADR 0016): atak na zamek-bota z planem (`plan`, opcjonalnie `general` i `sim_version`, jak w
// launch_attack) idzie przez `public.begin_bot_attack`, która w tej samej transakcji zatwierdza plan.
// Odpowiedź oddaje wtedy plan, badania, generała i perk władcy z zamku na serwerze, z których telefon
// liczy bitwę, a worker weryfikacji tę samą bitwę jeszcze raz. Bez planu (starszy klient) jak dotąd.
// #427 (ADR 0019): z planem odpowiedź mówi też (`server_losses`), czy straty armii odejmie serwer.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

const ALLOWED_KEYS = new Set(["defender_id", "bot_idx", "army", "plan", "general", "sim_version"]);
// jak w launch_attack: Generals.Kind, AttackPlan.MAX_SQUADS_BY_AGE[-1], kod wersji do 99.99.99
const MAX_GENERAL = 2;
const MAX_ORDERS = 8;
const MAX_SIM_VERSION = 999999;
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
  // #274: zamek atakującego na serwerze spoza limitów surowców (zapis sprzed reguł) nie wchodzi do PvP
  castle_invalid: 409,
  // #386: zamek-bot powyżej postępu kampanii na serwerze (players.bots_beaten)
  bot_locked: 409,
  target_not_found: 404,
  attacker_not_found: 404,
  army_not_owned: 400,
  bad_army: 400,
  bad_target: 400,
  self_attack: 400,
  bad_seed: 500,
  // #413: zatwierdzenie planu ataku na bota (launch_attack w begin_bot_attack)
  bad_plan: 400,
  bad_general: 400,
  unsupported_version: 409,
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
  // BotRoster.COUNT = 40 (#230: 20 zamków na epokę I–II); bazę pilnuje check na bot_castles.idx
  if (botIdx != null && (botIdx < 0 || botIdx > 39)) {
    return json({ error: "bad_bot" }, 400);
  }
  // kształt i zakresy armii sprawdza begin_attack; tu tylko rozmiar żądania
  if (!Array.isArray(b.army) || b.army.length < 1 || b.army.length > 16) {
    return json({ error: "bad_army" }, 400);
  }

  // #413: plan tylko przy zamku-bocie; kształt i zakresy rozkazów sprawdza check_plan w bazie
  const withPlan = b.plan !== undefined;
  if ((withPlan || b.general !== undefined || b.sim_version !== undefined) && botIdx == null) {
    return json({ error: "unknown_field" }, 400);
  }
  if (withPlan && (!Array.isArray(b.plan) || b.plan.length < 1 || b.plan.length > MAX_ORDERS)) {
    return json({ error: "bad_plan" }, 400);
  }
  if (!withPlan && (b.general !== undefined || b.sim_version !== undefined)) {
    return json({ error: "bad_plan" }, 400);
  }
  let general: number | null = null;
  if (b.general !== undefined) {
    if (typeof b.general !== "number" || !Number.isInteger(b.general) || b.general < 0 || b.general > MAX_GENERAL) {
      return json({ error: "bad_general" }, 400);
    }
    general = b.general;
  }
  let simVersion: number | null = null;
  if (b.sim_version !== undefined) {
    const v = b.sim_version;
    if (typeof v !== "number" || !Number.isInteger(v) || v < 1 || v > MAX_SIM_VERSION) {
      return json({ error: "bad_sim_version" }, 400);
    }
    simVersion = v;
  }

  // seed bitwy z kryptograficznego źródła; osobny od map_seed
  const battleSeed = crypto.getRandomValues(new Uint32Array(1))[0]! & 0x7fffffff;

  const admin = createClient(supabaseUrl, serviceKey);
  if (await clientOutdated(req, admin)) {
    return json({ error: "update_required" }, 426);
  }
  const { data, error } = withPlan
    ? await admin.rpc("begin_bot_attack", {
      p_attacker: attackerId,
      p_bot: botIdx,
      p_army: b.army,
      p_battle_seed: battleSeed,
      p_plan: b.plan,
      p_general: general,
      p_sim_version: simVersion,
    })
    : await admin.rpc("begin_attack", {
      p_attacker: attackerId,
      p_defender: defenderId,
      p_bot: botIdx,
      p_army: b.army,
      p_battle_seed: battleSeed,
    });
  if (error) {
    const code = known(error);
    if (code === "bot_locked") {
      const { data: me, error: meErr } = await admin.from("players").select("bots_beaten")
        .eq("id", attackerId).maybeSingle();
      if (meErr || !me || typeof me.bots_beaten !== "number") {
        console.error("start_attack bots_beaten", meErr?.code ?? "no_player");
        return json({ error: code }, ERRORS[code]!);
      }
      return json({ error: code, bots_beaten: me.bots_beaten }, ERRORS[code]!);
    }
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
    const { data: prev, error: prevErr } = await admin.rpc("attack_preview", {
      p_attacker: attackerId,
      p_attack: row.attack_id,
    });
    const view = Array.isArray(prev) ? prev[0] : null;
    if (prevErr || !view || !Array.isArray(view.keep)) {
      console.error("start_attack preview", prevErr?.code ?? "no_keep");
      return json({ error: "start_failed" }, 500);
    }
    payload.footprint = view.footprint ?? [];
    payload.keep = view.keep;
    payload.intel = view.intel ?? {};
  } else {
    payload.bot_idx = botIdx;
    if (withPlan) {
      // dane bitwy zatwierdzone na serwerze (#413): z nich telefon i worker liczą tę samą bitwę
      payload.plan = row.plan ?? [];
      payload.techs = row.techs ?? [];
      payload.general = row.general ?? null;
      payload.ruler_perk = row.ruler_perk ?? -1;
      // #427 (ADR 0019): straty armii odejmie serwer przy zapisie zamku
      payload.server_losses = row.server_losses === true;
    }
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

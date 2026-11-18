// start_attack (#166 / część #25): zapisuje atak po stronie serwera i zwraca seed terenu
// obrońcy (`map_seed`) osobno od seeda bitwy (`battle_seed`). Atakujący buduje z nich ten sam
// teren i deterministyczną bitwę. Pełne limity tarcz / doboru przeciwnika / finish_attack: #25.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
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

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const defenderId = typeof body.defender_id === "string" ? body.defender_id : null;
  const botIdx = typeof body.bot_idx === "number" && Number.isInteger(body.bot_idx)
    ? body.bot_idx as number
    : null;
  const army = Array.isArray(body.army) ? body.army : [];

  if ((defenderId == null) === (botIdx == null)) {
    return json({ error: "target_required" }, 400);
  }
  if (defenderId != null && defenderId === attackerId) {
    return json({ error: "self_attack" }, 400);
  }
  if (botIdx != null && (botIdx < 0 || botIdx > 19)) {
    return json({ error: "bad_bot" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);

  let mapSeed: number;
  let defenseSnapshot: Record<string, unknown> | null = null;
  let castleSnapshot: Record<string, unknown> | null = null;

  if (botIdx != null) {
    const { data: bot, error } = await admin.from("bot_castles").select("map_seed").eq("idx", botIdx)
      .maybeSingle();
    if (error || !bot) {
      return json({ error: "bot_not_found" }, 404);
    }
    mapSeed = Number(bot.map_seed);
  } else {
    const { data: castle, error: castleErr } = await admin.from("castles")
      .select("map_seed, data").eq("player_id", defenderId!).maybeSingle();
    if (castleErr || !castle) {
      return json({ error: "defender_not_found" }, 404);
    }
    mapSeed = Number(castle.map_seed);
    castleSnapshot = (castle.data ?? {}) as Record<string, unknown>;
    const { data: defense } = await admin.from("defense_layouts")
      .select("data").eq("player_id", defenderId!).maybeSingle();
    defenseSnapshot = (defense?.data ?? {}) as Record<string, unknown>;
  }

  if (!Number.isInteger(mapSeed) || mapSeed < 0 || mapSeed > 2147483647) {
    return json({ error: "bad_map_seed" }, 500);
  }

  // seed bitwy z kryptograficznego źródła; osobny od map_seed
  const battleSeed = crypto.getRandomValues(new Uint32Array(1))[0]! & 0x7fffffff;

  const row: Record<string, unknown> = {
    attacker_id: attackerId,
    battle_seed: battleSeed,
    map_seed: mapSeed,
    attacker_army: army,
    orders: [],
    status: "started",
  };
  if (botIdx != null) {
    row.bot_idx = botIdx;
  } else {
    row.defender_id = defenderId;
    row.defense_snapshot = defenseSnapshot;
    row.castle_snapshot = castleSnapshot;
  }

  const { data: attack, error: insertErr } = await admin.from("attacks").insert(row).select(
    "id, map_seed, battle_seed, defender_id, bot_idx",
  ).single();
  if (insertErr || !attack) {
    console.error("start_attack insert", insertErr?.message);
    return json({ error: "insert_failed" }, 500);
  }

  // bez kluczy null — klient z has()/filtrami typu nie dostaje fałszywego bot_idx: 0
  const payload: Record<string, unknown> = {
    id: attack.id,
    map_seed: attack.map_seed,
    battle_seed: attack.battle_seed,
  };
  if (attack.defender_id != null) {
    payload.defender_id = attack.defender_id;
  }
  if (attack.bot_idx != null) {
    payload.bot_idx = attack.bot_idx;
  }
  return json(payload);
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

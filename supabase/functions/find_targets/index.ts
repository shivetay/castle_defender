// find_targets (#24): dobór przeciwnika do ataku PvP. Zwraca do 3 graczy z `match_targets`
// (bez tarczy, ta sama epoka (#383), ranking ±100, nieatakowanych przez gracza w 24 h, limit 20 szukań na
// 10 minut: odpowiedź 429). Id atakującego idzie
// wyłącznie z tokenu, nigdy z treści żądania. Mniej niż 3 celów gra uzupełnia zamkami-botami.
// Karta dostaje siłę obrony celu tylko jako dolną granicę przedziału (#293, `strength`, mgła wojny).
// Zapisuje tylko licznik szukań (limit); blokada celu i tarcze po ataku są w start_attack / finish_attack (#25).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { clientOutdated } from "../_shared/client_version.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-client-version, apikey, content-type",
};

const MAX_TARGETS = 3;
const MAX_FOOTPRINT = 400;

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

  const admin = createClient(supabaseUrl, serviceKey);
  if (await clientOutdated(req, admin)) {
    return json({ error: "update_required" }, 426);
  }
  const { data, error } = await admin.rpc("match_targets", { p_attacker: userData.user.id });
  // P0001 to kod `raise exception` w match_targets; treść sprawdzamy z includes, bo PostgREST
  // może dodać prefiks albo przenieść ją do details
  const limited = error?.code === "P0001" &&
    `${error.message ?? ""} ${error.details ?? ""}`.includes("rate_limited");
  if (limited) {
    // limit z match_targets: 20 szukań na 10 minut
    return json({ error: "rate_limited" }, 429);
  }
  if (error || !Array.isArray(data)) {
    console.error("find_targets rpc", error?.code);
    return json({ error: "match_failed" }, 500);
  }

  const targets = data.slice(0, MAX_TARGETS).map((row: Record<string, unknown>) => ({
    player_id: String(row.player_id ?? ""),
    nickname: String(row.nickname ?? ""),
    castle_name: String(row.castle_name ?? ""),
    ruler: String(row.ruler ?? ""),
    age: Number(row.age ?? 0),
    rating: Number(row.rating ?? 0),
    map_seed: Number(row.map_seed ?? 0),
    footprint: Array.isArray(row.footprint) ? row.footprint.slice(0, MAX_FOOTPRINT) : [],
    loot: Array.isArray(row.loot) ? row.loot : [],
    strength: Number.isInteger(row.strength) ? row.strength : null,
  }));
  return json({ targets });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// scout_reports (#28): misje zwiadu gracza z ostatniej doby z `public.scout_reports` (id z tokenu).
// Misja w drodze ma tylko czas do końca; wynik, ocaleli i odsłonięte dane serwer oddaje po końcu.
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
  const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: auth } } });
  const { data: userData, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userData.user) {
    return json({ error: "unauthorized" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const { data, error } = await admin.rpc("scout_reports", { p_attacker: userData.user.id });
  if (error) {
    console.error("scout_reports rpc", error.code);
    return json({ error: "reports_failed" }, 500);
  }
  const now = Date.now();
  const rows = (Array.isArray(data) ? data : []).map((r) => {
    const out: Record<string, unknown> = {
      id: r.mission_id,
      defender_id: r.defender_id,
      castle_name: r.castle_name ?? "",
      duration: r.duration,
      trackers: r.trackers,
      scouts: r.scouts,
      finished: r.finished === true,
      remaining_s: Math.max(0, Math.ceil((Date.parse(r.ends_at) - now) / 1000)),
    };
    if (r.finished === true) {
      out.outcome = r.outcome;
      out.percent = r.percent;
      out.returned = r.returned;
      out.intel = r.intel ?? {};
    }
    return out;
  });
  return json({ reports: rows });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
}

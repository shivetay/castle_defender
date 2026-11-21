// ranking (#27, #242): tabela rankingu w epoce gracza: PvP osobno za atak i za obronę albo PvE (punkty
// za zamki-boty). Id gracza idzie wyłącznie z tokenu, nigdy z treści żądania.
// Treść: {"kind": "attack" | "defense" | "pve"}.
// Odpowiedź: {"kind", "rows": [{place, nickname, castle_name, ruler, points, is_me}]}: 20 najlepszych
// z `pvp_ranking` albo `pve_ranking` i własny wiersz gracza, gdy jest niżej. Bez id innych graczy.
// Niczego nie zapisuje.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const KINDS = new Set(["attack", "defense", "pve"]);
// RANKING_TOP = 20 i własny wiersz
const MAX_ROWS = 21;

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
  if (Object.keys(b).some((k) => k !== "kind") || typeof b.kind !== "string" || !KINDS.has(b.kind)) {
    return json({ error: "bad_kind" }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey);
  const { data, error } = b.kind === "pve"
    ? await admin.rpc("pve_ranking", { p_player: userData.user.id })
    : await admin.rpc("pvp_ranking", { p_player: userData.user.id, p_kind: b.kind });
  if (error || !Array.isArray(data)) {
    console.error("ranking rpc", error?.code);
    return json({ error: "ranking_failed" }, 500);
  }

  const rows = data.slice(0, MAX_ROWS).map((row: Record<string, unknown>) => ({
    place: Number(row.place ?? 0),
    nickname: String(row.nickname ?? ""),
    castle_name: String(row.castle_name ?? ""),
    ruler: String(row.ruler ?? ""),
    points: Number(row.points ?? 0),
    is_me: row.is_me === true,
  }));
  return json({ kind: b.kind, rows });
});

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

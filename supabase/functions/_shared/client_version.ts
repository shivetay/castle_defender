// Wymuszenie aktualizacji (#336, ADR 0005): wersja klienta z nagłówka `X-Client-Version` porównana
// z `min_code` z `public.client_version_policy()`. Brak nagłówka albo coś innego niż liczba to 0,
// czyli wersja sprzed #336. Funkcja woła to po sprawdzeniu tokenu i przy `true` odpowiada
// 426 `{"error": "update_required"}`. Błąd odczytu progów przepuszcza żądanie (bez progów gra działa
// jak dotąd); minimum trzymamy w pamięci instancji najwyżej CACHE_MS.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const CACHE_MS = 60_000;
let cachedMin = 0;
let cachedAt = -Infinity;

export function clientCode(req: Request): number {
  const raw = (req.headers.get("x-client-version") ?? "").trim();
  return /^[0-9]{1,9}$/.test(raw) ? Number(raw) : 0;
}

export async function clientOutdated(req: Request, admin: SupabaseClient): Promise<boolean> {
  const now = Date.now();
  if (now - cachedAt > CACHE_MS) {
    const { data, error } = await admin.rpc("client_version_policy");
    if (error) {
      console.error("client_version_policy rpc", error.code);
      return false;
    }
    const min = Number((data as Record<string, unknown> | null)?.min_code ?? 0);
    cachedMin = Number.isFinite(min) ? min : 0;
    cachedAt = now;
  }
  return clientCode(req) < cachedMin;
}

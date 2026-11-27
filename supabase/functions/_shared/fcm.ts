// Push przez Firebase Cloud Messaging HTTP v1 (#30, ADR 0012).
//
// Konto serwisowe Firebase (JSON z `project_id`, `client_email`, `private_key`) leży wyłącznie
// w sekrecie Edge Functions `FCM_SERVICE_ACCOUNT`, nigdy w repo ani w kliencie. Bez sekretu wysyłka
// po cichu się nie odbywa (gra działa jak przed #30). Token OAuth (JWT RS256 podpisany WebCrypto,
// wymieniony w oauth2.googleapis.com) trzymamy w pamięci instancji do 5 minut przed wygaśnięciem.
// Do logów idzie tylko kod błędu: bez tokenów urządzeń, treści i id graczy.
import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

const FCM_SCOPE = "https://www.googleapis.com/auth/firebase.messaging";
const TOKEN_URL = "https://oauth2.googleapis.com/token";

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

let cachedToken = "";
let cachedUntil = 0;

/** Treść pusha o ataku na zamek; `won` jest z perspektywy atakującego. */
export function attackMessage(won: boolean, percent: number): { title: string; body: string } {
  const p = Math.max(0, Math.min(100, Math.trunc(percent)));
  return {
    title: "Twój zamek został zaatakowany!",
    body: won ? `Donżon zdobyty (${p}%)` : `Obrona odparta (${p}%)`,
  };
}

/** Wiadomość FCM v1: wspólny klucz i tag `attack`, więc kolejny atak zastępuje poprzednie powiadomienie. */
export function attackPayload(token: string, won: boolean, percent: number): Record<string, unknown> {
  const { title, body } = attackMessage(won, percent);
  return {
    message: {
      token,
      notification: { title, body },
      data: { kind: "attack" },
      android: {
        priority: "high",
        collapse_key: "attack",
        notification: { tag: "attack", channel_id: "attacks" },
      },
    },
  };
}

/** Czy odpowiedź FCM oznacza martwy token (urządzenie odinstalowało grę albo token jest zły). */
export function isDeadToken(status: number, body: string): boolean {
  if (status === 404 || body.includes("UNREGISTERED")) {
    return true;
  }
  return status === 400 && body.includes("INVALID_ARGUMENT") && /registration token/i.test(body);
}

function serviceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "";
  if (!raw) {
    return null;
  }
  try {
    const sa = JSON.parse(raw) as Partial<ServiceAccount>;
    if (typeof sa.project_id === "string" && typeof sa.client_email === "string" &&
        typeof sa.private_key === "string") {
      return sa as ServiceAccount;
    }
  } catch {
    // niżej
  }
  console.error("fcm bad_service_account");
  return null;
}

function b64url(bytes: Uint8Array | string): string {
  const bin = typeof bytes === "string" ? bytes : String.fromCharCode(...bytes);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function accessToken(sa: ServiceAccount): Promise<string | null> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && now < cachedUntil - 300) {
    return cachedToken;
  }
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false, ["sign"]);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = b64url(JSON.stringify({
    iss: sa.client_email, scope: FCM_SCOPE, aud: TOKEN_URL, iat: now, exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${b64url(sig)}`,
    }),
  });
  if (!res.ok) {
    console.error("fcm oauth", res.status);
    return null;
  }
  const data = await res.json() as { access_token?: string; expires_in?: number };
  if (typeof data.access_token !== "string") {
    return null;
  }
  cachedToken = data.access_token;
  cachedUntil = now + (Number(data.expires_in) || 3600);
  return cachedToken;
}

/**
 * Push do obrońcy po zakończonym ataku. `attack_push_claim` oznacza atak jako powiadomiony tylko raz,
 * więc ponowione `finish_attack` nic nie wyśle. Martwe tokeny usuwa `push_token_drop`. Nigdy nie rzuca.
 */
export async function notifyDefender(admin: SupabaseClient, attacker: string, attack: string): Promise<void> {
  try {
    const sa = serviceAccount();
    if (!sa) {
      return;
    }
    const { data, error } = await admin.rpc("attack_push_claim", { p_attacker: attacker, p_attack: attack });
    if (error) {
      console.error("attack_push_claim rpc", error.code);
      return;
    }
    const rows = Array.isArray(data) ? data as { token: string; won: boolean; percent: number }[] : [];
    if (rows.length === 0) {
      return;
    }
    const bearer = await accessToken(sa);
    if (!bearer) {
      return;
    }
    const url = `https://fcm.googleapis.com/v1/projects/${encodeURIComponent(sa.project_id)}/messages:send`;
    await Promise.all(rows.map(async (row) => {
      const res = await fetch(url, {
        method: "POST",
        headers: { Authorization: `Bearer ${bearer}`, "Content-Type": "application/json" },
        body: JSON.stringify(attackPayload(row.token, row.won === true, Number(row.percent) || 0)),
      });
      if (res.ok) {
        await res.body?.cancel();
        return;
      }
      const text = await res.text();
      if (isDeadToken(res.status, text)) {
        const { error: dropErr } = await admin.rpc("push_token_drop", { p_token: row.token });
        if (dropErr) {
          console.error("push_token_drop rpc", dropErr.code);
        }
      } else {
        console.error("fcm send", res.status);
      }
    }));
  } catch (e) {
    console.error("fcm notify", e instanceof Error ? e.name : "error");
  }
}

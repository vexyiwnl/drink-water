// sync-ping: called by Database Webhooks when a user's entries/day_sessions/settings
// change. Sends a silent FCM data message to that user's phones, so a closed phone
// app wakes up, syncs and re-plans its reminder alarms.
//
// Secrets (Edge Functions → Secrets):
//   FCM_SERVICE_ACCOUNT  full JSON of a Firebase service-account key
//   WEBHOOK_SECRET       random string; the webhooks send it as `x-webhook-secret`
// Deploy with "Verify JWT" OFF: the webhook secret is the authentication.

import { createClient } from "npm:@supabase/supabase-js@2";

const sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT")!);
const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
const json64 = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));

let cached: { token: string; expires: number } | null = null;

/** OAuth access token for FCM, from the service account (signed JWT → token exchange). */
async function accessToken(): Promise<string> {
  if (cached && cached.expires > Date.now() + 60_000) return cached.token;
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${json64({ alg: "RS256", typ: "JWT" })}.${json64({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  })}`;
  const der = Uint8Array.from(atob(sa.private_key.replace(/-----[^-]+-----|\s/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${b64url(sig)}`,
    }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`Google OAuth failed: ${JSON.stringify(body)}`);
  cached = { token: body.access_token, expires: Date.now() + body.expires_in * 1000 };
  return cached.token;
}

Deno.serve(async (req) => {
  if (req.headers.get("x-webhook-secret") !== Deno.env.get("WEBHOOK_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }
  const { record, old_record } = await req.json();
  const userId = (record ?? old_record)?.user_id;
  if (!userId) return new Response("no user_id in payload", { status: 400 });

  const { data: devices, error } = await db.from("devices").select("token").eq("user_id", userId);
  if (error) return new Response(error.message, { status: 500 });
  if (!devices?.length) return new Response("no devices");

  const auth = await accessToken();
  const results = await Promise.all(devices.map(async ({ token }) => {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${auth}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          data: { type: "sync" },
          // collapse_key: a burst of changes delivers as one ping.
          android: { priority: "high", collapse_key: "sync", ttl: "600s" },
        },
      }),
    });
    if (res.status === 404) await db.from("devices").delete().eq("token", token); // app uninstalled
    return res.status;
  }));
  return new Response(`sent: ${results.join(",")}`);
});

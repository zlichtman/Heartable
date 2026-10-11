// Returns a fresh Apple Music developer token (ES256 JWT) signed with the
// .p8 key stored as a Supabase secret. The .p8 never leaves the edge runtime.
//
// Required secrets (set via `supabase secrets set` or the dashboard):
//   APPLE_MUSIC_KEY_ID       — 10-char Key ID from developer.apple.com › Keys
//   APPLE_MUSIC_TEAM_ID      — 10-char Team ID (Membership page)
//   APPLE_MUSIC_PRIVATE_KEY  — the full PEM contents of the .p8 key file
//
// Apple caps the dev token at 6 months. We sign for 6 months minus a day so
// the client has time to refetch before the cliff. Caller must present a
// valid Supabase JWT — verify_jwt=true on the function does that for us.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function b64url(input: Uint8Array | string): string {
  const bytes =
    typeof input === "string" ? new TextEncoder().encode(input) : input;
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/=+$/, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToPkcs8(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/g, "")
    .replace(/-----END [^-]+-----/g, "")
    .replace(/\s+/g, "");
  const bin = atob(body);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

async function signAppleMusicToken(): Promise<{
  token: string;
  expiresAt: number;
}> {
  const keyId = Deno.env.get("APPLE_MUSIC_KEY_ID");
  const teamId = Deno.env.get("APPLE_MUSIC_TEAM_ID");
  const privateKey = Deno.env.get("APPLE_MUSIC_PRIVATE_KEY");
  if (!keyId || !teamId || !privateKey) {
    throw new Error(
      "Missing APPLE_MUSIC_KEY_ID / APPLE_MUSIC_TEAM_ID / APPLE_MUSIC_PRIVATE_KEY secrets.",
    );
  }

  const now = Math.floor(Date.now() / 1000);
  const exp = now + 60 * 60 * 24 * 180 - 60 * 60 * 24; // 6 months minus 1 day

  const header = { alg: "ES256", kid: keyId };
  const payload = { iss: teamId, iat: now, exp };

  const headerEnc = b64url(JSON.stringify(header));
  const payloadEnc = b64url(JSON.stringify(payload));
  const signingInput = `${headerEnc}.${payloadEnc}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(privateKey),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  );
  const token = `${signingInput}.${b64url(new Uint8Array(sig))}`;
  return { token, expiresAt: exp };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405, headers: CORS });
  }
  try {
    const { token, expiresAt } = await signAppleMusicToken();
    return new Response(JSON.stringify({ token, expiresAt }), {
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : "Unknown error";
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
});

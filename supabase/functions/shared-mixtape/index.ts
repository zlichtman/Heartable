// A public endpoint authenticated by an unguessable, revocable bearer link.
// No request bodies, tokens, or mixtape contents are logged.
const headers = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Access-Control-Allow-Origin": "https://heartable-mixtapes.zlichtman.chatgpt.site",
  "Access-Control-Allow-Headers": "content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Referrer-Policy": "no-referrer",
};
const reply = (data: unknown, status = 200) => new Response(JSON.stringify(data), { status, headers });

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers });
  if (request.method !== "POST") return reply({ error: "Not found" }, 404);
  try {
    // Bound actual bytes rather than trusting Content-Length.
    const reader = request.body?.getReader();
    if (!reader) return reply({ error: "Invalid link" }, 400);
    let body = "";
    const decoder = new TextDecoder();
    let bytes = 0;
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      bytes += value.byteLength;
      if (bytes > 256) { await reader.cancel(); return reply({ error: "Invalid link" }, 400); }
      body += decoder.decode(value, { stream: true });
    }
    body += decoder.decode();
    const token = JSON.parse(body).token;
    if (typeof token !== "string" || !/^[0-9a-f]{64}$/.test(token)) return reply({ error: "Invalid link" }, 400);
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token))))
      .map(b => b.toString(16).padStart(2, "0")).join("");
    const base = Deno.env.get("SUPABASE_URL")!;
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const auth = { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" };
    const response = await fetch(`${base}/rest/v1/rpc/read_shared_mixtape`, {
      method: "POST", headers: auth, body: JSON.stringify({ p_hash: hash }),
      signal: AbortSignal.timeout(8000),
    });
    if (!response.ok) return reply({ error: "Try again shortly" }, 503);
    const snapshot = await response.json();
    if (!snapshot) return reply({ error: "This link is no longer available" }, 404);
    const mediaPattern = /^heartable-media:\/\/mixtape-gifts\/([0-9a-f-]{36}\/[0-9a-f-]{36}\/[0-9a-f-]{36}\.jpg)$/;
    async function image(reference: unknown): Promise<string | null> {
      if (typeof reference !== "string") return null;
      const match = mediaPattern.exec(reference);
      if (!match) return null;
      const result = await fetch(`${base}/storage/v1/object/sign/mixtape-gifts/${match[1]}`, {
        method: "POST", headers: auth, body: JSON.stringify({ expiresIn: 60 }),
        signal: AbortSignal.timeout(5000),
      });
      if (!result.ok) return null;
      const data = await result.json();
      return typeof data.signedURL === "string" ? `${base}/storage/v1${data.signedURL}` : null;
    }
    snapshot.cover_url = await image(snapshot.cover_url);
    // Small batches bound concurrent Storage calls even for a large mixtape.
    for (let i = 0; i < snapshot.tracks.length; i += 8) {
      await Promise.all(snapshot.tracks.slice(i, i + 8).map(async (track: Record<string, unknown>) => {
        track.note_image_url = await image(track.note_image_url);
      }));
    }
    return reply(snapshot);
  } catch { return reply({ error: "Couldn’t open this mixtape. Try again." }, 400); }
});

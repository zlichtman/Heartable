import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

async function spotifyFetch(url: string, token: string, init?: RequestInit, retries = 3): Promise<any> {
  const res = await fetch(url, { ...init, headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json", ...init?.headers } });
  if (res.status === 429 && retries > 0) {
    const secs = parseInt(res.headers.get("Retry-After") || "3", 10);
    const waitMs = Math.min(secs, 15) * 1000;
    await new Promise(r => setTimeout(r, waitMs));
    return spotifyFetch(url, token, init, retries - 1);
  }
  if (!res.ok) {
    const text = await res.text();
    console.error(`Spotify ${res.status} on ${url}:`, text);
    throw new Error(`Spotify ${res.status}: ${text}`);
  }
  // Spotify PUT /me/tracks returns 200 with an empty body; guard the json parse.
  const text = await res.text();
  return text ? JSON.parse(text) : {};
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  try {
    const { spotifyToken, snapshotId, supabaseAccessToken } = await req.json();

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    if (!supabaseAccessToken) return json({ error: "Not signed in" }, 401);
    const { data: userData, error: userErr } = await supabase.auth.getUser(supabaseAccessToken);
    const owner = userData?.user?.id;
    if (userErr || !owner) return json({ error: "Invalid session" }, 401);

    // Only the snapshot's owner may restore it.
    const { data: snap } = await supabase
      .from("library_snapshots")
      .select("id, owner")
      .eq("id", snapshotId)
      .maybeSingle();
    if (!snap) return json({ error: "Snapshot not found" }, 404);
    if (snap.owner !== owner) return json({ error: "Not your snapshot" }, 403);

    const me = await spotifyFetch("https://api.spotify.com/v1/me", spotifyToken);
    console.log(`Restore: user=${me.id}, snapshot=${snapshotId}`);

    const { data: playlists } = await supabase
      .from("snapshot_playlists")
      .select("id, spotify_playlist_id, name, description, is_public")
      .eq("snapshot_id", snapshotId);

    const restored: string[] = [];
    const errors: string[] = [];

    for (const pl of (playlists ?? [])) {
      try {
        const newPl = await spotifyFetch(
          "https://api.spotify.com/v1/me/playlists",
          spotifyToken,
          {
            method: "POST",
            body: JSON.stringify({
              name: pl.name,
              description: pl.description ?? "",
              public: pl.is_public ?? false,
            }),
          },
        );

        const { data: tracks } = await supabase
          .from("snapshot_tracks")
          .select("spotify_track_uri, position")
          .eq("snapshot_playlist_id", pl.id)
          .order("position");

        if (tracks?.length) {
          const uris = tracks.map((t: any) => t.spotify_track_uri).filter(Boolean);
          for (let i = 0; i < uris.length; i += 100) {
            await spotifyFetch(
              `https://api.spotify.com/v1/playlists/${newPl.id}/items`,
              spotifyToken,
              { method: "POST", body: JSON.stringify({ uris: uris.slice(i, i + 100) }) },
            );
          }
        }

        restored.push(pl.name);
      } catch (e) {
        console.error(`Failed to restore playlist ${pl.name}:`, e);
        errors.push(`${pl.name}: ${String(e)}`);
      }
    }

    // Restore saved ("liked") tracks back into the Spotify library. These were
    // captured on the snapshot directly; re-save them with PUT /me/tracks (max
    // 50 ids per call). Preserve order by saving oldest-first.
    const { data: likedTracks } = await supabase
      .from("snapshot_liked_tracks")
      .select("spotify_track_uri, position")
      .eq("snapshot_id", snapshotId)
      .order("position");

    let likedRestored = 0;
    if (likedTracks?.length) {
      const ids = likedTracks
        .map((t: any) => t.spotify_track_uri)
        .filter((u: any) => typeof u === "string" && u.startsWith("spotify:track:"))
        .map((u: string) => u.split(":")[2])
        .filter(Boolean);
      for (let i = 0; i < ids.length; i += 50) {
        const batch = ids.slice(i, i + 50);
        try {
          await spotifyFetch(
            "https://api.spotify.com/v1/me/tracks",
            spotifyToken,
            { method: "PUT", body: JSON.stringify({ ids: batch }) },
          );
          likedRestored += batch.length;
        } catch (e) {
          console.error(`Failed to restore liked batch ${i}:`, e);
          errors.push(`liked tracks ${i + 1}-${i + batch.length}: ${String(e)}`);
        }
      }
    }

    const totalPlaylists = playlists?.length ?? 0;
    if (totalPlaylists === 0 && (likedTracks?.length ?? 0) === 0) {
      return json({ error: "Nothing to restore in this snapshot" }, 404);
    }

    return json({
      restored,
      total: restored.length,
      totalPlaylists,
      likedRestored,
      errors: errors.length > 0 ? errors : undefined,
    });
  } catch (err) {
    console.error("Restore error:", err);
    return json({ error: String(err) }, 500);
  }
});

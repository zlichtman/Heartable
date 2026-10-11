import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// Permanently deletes the caller's account: every row they own across the public
// schema, their storage objects, and finally the auth.users record. Authenticates
// the caller by the Authorization bearer token (their Supabase session JWT) and
// only ever deletes that user's own data. Service role bypasses RLS so the wipe
// is complete even where ON DELETE CASCADE isn't configured.
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  try {
    const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json({ error: "Missing Authorization bearer token" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      { auth: { autoRefreshToken: false, persistSession: false } },
    );

    const { data: userData, error: uErr } = await admin.auth.getUser(jwt);
    if (uErr || !userData?.user) return json({ error: "Invalid or expired session" }, 401);
    const uid = userData.user.id;

    // ---- owned data, children first (service role bypasses RLS) ----
    // Library snapshots and their grandchildren.
    const { data: snaps } = await admin.from("library_snapshots").select("id").eq("owner", uid);
    const snapIDs = (snaps ?? []).map((r: any) => r.id);
    if (snapIDs.length) {
      const { data: pls } = await admin.from("snapshot_playlists").select("id").in("snapshot_id", snapIDs);
      const plIDs = (pls ?? []).map((r: any) => r.id);
      if (plIDs.length) await admin.from("snapshot_tracks").delete().in("snapshot_playlist_id", plIDs);
      await admin.from("snapshot_liked_tracks").delete().in("snapshot_id", snapIDs);
      await admin.from("snapshot_playlists").delete().in("snapshot_id", snapIDs);
    }
    await admin.from("library_snapshots").delete().eq("owner", uid);

    // Mixtapes + children, plus shares received from others.
    const { data: tapes } = await admin.from("mixtapes").select("id").eq("owner", uid);
    const tapeIDs = (tapes ?? []).map((r: any) => r.id);
    if (tapeIDs.length) {
      await admin.from("mixtape_tracks").delete().in("mixtape_id", tapeIDs);
      await admin.from("mixtape_shares").delete().in("mixtape_id", tapeIDs);
    }
    await admin.from("mixtape_shares").delete().eq("shared_with", uid);
    await admin.from("mixtapes").delete().eq("owner", uid);

    // Playlist folders + items.
    const { data: folders } = await admin.from("playlist_folders").select("id").eq("owner", uid);
    const folderIDs = (folders ?? []).map((r: any) => r.id);
    if (folderIDs.length) await admin.from("playlist_folder_items").delete().in("folder_id", folderIDs);
    await admin.from("playlist_folders").delete().eq("owner", uid);

    // Social + player data.
    await admin.from("track_skip_versions").delete().eq("owner", uid);
    await admin.from("now_playing").delete().eq("user_id", uid);
    await admin.from("play_log").delete().eq("user_id", uid);
    await admin.from("friendships").delete().or(`requester_id.eq.${uid},addressee_id.eq.${uid}`);
    await admin.from("profiles").delete().eq("user_id", uid);

    // Storage objects scoped to {uid}/ (best-effort; never blocks deletion).
    for (const bucket of ["avatars", "mixtape-media"]) {
      try {
        const { data: files } = await admin.storage.from(bucket).list(uid, { limit: 1000 });
        const paths = (files ?? []).map((f: any) => `${uid}/${f.name}`);
        if (paths.length) await admin.storage.from(bucket).remove(paths);
      } catch (_) { /* ignore */ }
    }

    // Finally, remove the auth user itself.
    const { error: dErr } = await admin.auth.admin.deleteUser(uid);
    if (dErr) return json({ error: `deleteUser: ${dErr.message}` }, 500);

    return json({ ok: true, userId: uid });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

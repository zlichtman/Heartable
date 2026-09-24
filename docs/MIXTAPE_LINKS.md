# Shared mixtape links

## Access contract

- Drafts remain owner-only. Publish explicitly creates a snapshot of title,
  dedication, ordered tracks, notes, and uploaded cover/note images.
- Updating a shared version preserves the link. Editing a draft alone does not
  update the snapshot. Revoking removes the link; publishing again generates a
  new 256-bit token.
- Anyone holding the token can read that version without signing in. This is
  bearer access, not recipient identity verification or DRM. Recipients can save
  copies. Signed image URLs last 60 seconds; revocation cannot recall downloads.
- Tokens are URL fragments, not query parameters in browser requests. The viewer
  POSTs the token to the Edge Function. Do not add analytics or token/body logging.
- Owners manage links through an authenticated RPC. The private table has no
  client privileges and deny-by-default RLS. Only the server role can invoke the
  snapshot-read RPC. Private provider stream URLs are not published.
- Native read-only viewing works before login. Playback requires the appropriate
  connected provider and its permissions; no cross-provider entitlement is implied.

## Deployment

Canonical source: `web/mixtapes` in `zlichtman/Heartable`. Sites project:
`appgprj_6a9df18d81e48191ac6b6d361aa4673d`.

The viewer build passed after updating the starter's dependencies; `npm audit`
reported zero vulnerabilities. Authored pages pass lint. Whole-starter lint still
reports pre-existing issues in unused vendored components; no such component is
imported by the viewer. Keep package versions and lockfile pinned.

The [public viewer](https://heartable-mixtapes.zlichtman.chatgpt.site) was deployed
with explicit approval on September 6, 2026. The site source delivery mirror is not a
second GitHub product repository. Use Sites' source/version/deployment workflow.

The `shared-mixtape` Edge Function is deployed with gateway JWT verification off
because the function implements its own strict bearer-token authentication. It
does not grant anonymous database access. Match local/remote migrations before
release and deploy the function from `supabase/functions/shared-mixtape/index.ts`.

## Verification and remaining gates

- `supabase/tests/mixtape_links.sql`: rollback-only owner/stranger, private draft,
  snapshot isolation, token shape, privilege, and revoke tests passed.
- A synthetic live link returned only its fixture snapshot (HTTP 200); removing
  the fixture made the same link return HTTP 404. Invalid tokens return HTTP 400.
  Synthetic accounts were deleted and zero remaining fixture accounts verified.
- iOS parser tests and full 229-test suite passed. Simulator Release build passed.
- Physical iPhone acceptance still needed: open a shared URL, private image loads,
  provider playback, dismiss/reopen, edit/update/revoke, and vinyl transitions.
- No App Store/public TestFlight install link exists in this flow. The viewer
  truthfully asks people without the app to request a private-beta invite.

Supabase advisors still report existing public SECURITY DEFINER functions and
disabled leaked-password protection. They were not introduced by this change:
[function privilege guidance](https://supabase.com/docs/guides/database/database-linter?lint=0029_authenticated_security_definer_function_executable),
[password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
The private link/throttle tables intentionally have RLS enabled with no client
policies: [deny-by-default RLS notice](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

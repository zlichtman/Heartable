# Notification audit

Reviewed September 6, 2026. Changes are implemented locally; release verification
is tracked in `PUBLIC_BETA.md`.

## Current controls

| Event | Default | Delivery and control |
|---|---|---|
| Playback and failed-action errors | On | Actionable alerts; unaffected by routine mute, but always obey master and iOS settings. Identical errors coalesce for 15 seconds, including alternating error streams. |
| Saves, connections, and completed manual actions | On | Routine confirmations toggle; always silent. Identical feedback coalesces for 2 seconds. |
| Automatic backup complete | On | Separate automatic-backup toggle; manual backup results remain routine confirmations. |
| Weekly recap reminder | Off | Opt-in Sunday 6 PM local reminder. It invites a visit; it does not claim new server data exists. Existing explicit choices remain. |
| Sounds | On | Applies to errors, automatic backups, and reminders. Never adds sound to routine confirmations. |

The master switch applies to every category. Controls reflect real iOS
authorization, refresh on foreground, and link to Heartable's notification
settings for banners and Lock Screen; Focus may still delay delivery. Preferences are device-level,
not provider-account settings. All transient feedback goes through Apple's
notification system; there is no in-app toast fallback.

## Engineering changes

- A typed policy resolves categories consistently at enqueue and foreground
  presentation time. Errors cannot accidentally inherit a muted routine category.
- Reminder reconciliation is serialized and rechecks preferences after scheduling,
  avoiding stale reminders after quick toggles.
- Repeated failures are deduplicated across more than the immediately previous
  message. Empty messages are discarded; distinct failures remain visible.
- Muted messages do not consume a dedup window, so unmuting and immediately
  retrying an action allows its first notification.
- Removed the notification about opening notification settings and copy that
  implied unimplemented social push delivery.

## Worth adding after remote delivery exists

Friend requests, direct messages, and received Mixtapes are useful event-driven
alerts. They need APNs device registration, account-bound token cleanup, a
server-side event pipeline, authorization checks, and idempotent delivery first.
Those pushes are **not implemented** by this change. When added, provide separate
controls and conversation mute, avoid message/mixtape-photo previews by default,
and suppress duplicate alerts while the matching conversation is open.

Do not send a push for every friend play, chart movement, background refresh, or
routine screen opening. Listening activity belongs in the feed or an opted-in
digest, not a stream of interruptions.

## Verification

`HeartableNotificationTests` covers routing, blank/duplicate suppression,
alternating errors, category boundaries, master mute, foreground preference
changes, sound policy, and opt-in reminder migration. Physical-device checks
remain necessary for iOS presentation, Focus, provisional permission, and sounds.

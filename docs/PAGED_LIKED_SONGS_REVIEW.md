# Liked-song paging and unavailable tracks

## Confirmed code defects

The Spotify page decoder removes null and malformed entries before returning its items. The callers previously advanced `offset` by the surviving count and stopped when that filtered count reached zero. A page containing unavailable entries could therefore repeat source positions; an entirely unavailable page could incorrectly terminate a full-library read. The decoder now reports the original slot count, and all Spotify library pagination uses that count. A nonterminal page with zero source slots fails instead of claiming a complete library.

Liked songs were paginated over the network but accumulated as Spotify models until the entire pull finished. Only then were they converted to unified tracks and displayed. The new path converts and publishes each page before fetching the next, retaining only one raw Spotify page. Spotify browse loading is no longer truncated at 10,000 songs. The application still retains the accumulated normalized metadata needed by the library and indexes; this is not a disk-only library.

Partial pages add or update visible songs without proving removal. Only a complete successful result replaces that provider's snapshot. A later failure preserves prior cached songs plus received pages, shows the failure notice, and remains eligible for retry. Account/lifecycle checks reject late pages after reset.

The Heartables screen now uses a native recycling List with stable song IDs, rather than an enumerated whole-array copy inside a nested LazyVStack. Loading progress remains visible while pages arrive.

Spotify's `is_local`, `is_playable`, and restrictions metadata now survive normalization and local cache encoding. Local files and explicitly unavailable tracks remain inspectable, with a reason, but are excluded from provider queues and master-library source selection. Legacy cached Spotify local URIs and empty play handles are rejected too. Local rows lacking an ID use their URI for identity. Selecting an unavailable song does not silently play a different song.

## Verification

Regression fixtures cover null/malformed slots, a wholly null intermediate page, publication before the next request, failure after a successful page, 20,000 songs in batches of at most 50, local/restricted songs across all shuffle modes, cache compatibility, preservation after partial failure, and account-reset isolation.

## Remaining evidence and delivery

These defects are reproducible in code, but the reported device termination is not yet tied to a crash stack or memory-limit report. The App Store Connect browser session expired and the available local API keys were rejected, so new crash submissions and TestFlight distribution cannot currently be verified. A signed-in App Store Connect session and the tester's exact failing action/build are needed to close those checks.

Validation completed: all 282 simulator tests passed; the generic iOS Simulator Release build and release-identity validation passed. TestFlight delivery remains pending restored App Store Connect authentication; no new uploaded build is claimed.

#!/bin/sh

# Xcode Cloud runs this automatically after cloning, before resolving/ building.
# Config/Secrets.xcconfig is gitignored, so it isn't in the repo — the committed
# project references it as the base config. We regenerate it here from the
# workflow's environment variables (set them in App Store Connect → Xcode Cloud
# → Workflow → Environment, mark the values Secret):
#
#   SUPABASE_HOST       (optional, defaults below)
#   SUPABASE_ANON_KEY   (required)
#   SPOTIFY_CLIENT_ID   (required)
#   LASTFM_API_KEY      (optional)
#   LASTFM_USER         (optional)
#
# xcconfig treats `//` as a comment, so the Supabase URL is a bare host (no scheme).

set -e

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

"$REPO/ci_scripts/validate_release_identity.sh"

# Pasted secrets often carry stray newlines/spaces (long values wrap on paste),
# which breaks xcconfig parsing ("expected a '='"). Flatten each value to one line.
clean() {
  printf '%s' "$1" | tr -d '\r\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

HOST="$(clean "${SUPABASE_HOST:-ghmuafydukliccwamkrq.supabase.co}")"
ANON="$(clean "${SUPABASE_ANON_KEY}")"
SPOTIFY="$(clean "${SPOTIFY_CLIENT_ID}")"
LASTFM_KEY="$(clean "${LASTFM_API_KEY}")"
LASTFM_USERNAME="$(clean "${LASTFM_USER}")"

require_value() {
  key="$1"
  value="$2"
  if [ -z "$value" ]; then
    echo "ci_post_clone: missing required Xcode Cloud variable: $key" >&2
    exit 1
  fi
}

require_value "SUPABASE_HOST" "$HOST"
require_value "SUPABASE_ANON_KEY" "$ANON"
require_value "SPOTIFY_CLIENT_ID" "$SPOTIFY"

mkdir -p "$REPO/Config"
cat > "$REPO/Config/Secrets.xcconfig" <<EOF
SUPABASE_HOST = ${HOST}
SUPABASE_ANON_KEY = ${ANON}
SPOTIFY_CLIENT_ID = ${SPOTIFY}
LASTFM_API_KEY = ${LASTFM_KEY}
LASTFM_USER = ${LASTFM_USERNAME}
EOF

echo "ci_post_clone: wrote Config/Secrets.xcconfig (host=${HOST}, anon len=${#ANON}, spotify len=${#SPOTIFY})"

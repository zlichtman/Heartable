#!/bin/sh

set -eu

ROOT="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"

fail() {
  echo "release identity check failed: $1" >&2
  exit 1
}

require_literal() {
  file="$1"
  value="$2"
  grep -Fq "$value" "$ROOT/$file" ||
    fail "$file does not contain $value"
}

require_literal project.yml "name: Heartable"
require_literal project.yml "PRODUCT_BUNDLE_IDENTIFIER: com.zlichtman.heartable"
require_literal project.yml "PRODUCT_BUNDLE_IDENTIFIER: com.zlichtman.heartable.widget"
require_literal Heartable/Resources/Heartable.entitlements \
  "group.com.zlichtman.heartable"
require_literal HeartableWidget/HeartableWidget.entitlements \
  "group.com.zlichtman.heartable"
require_literal Heartable.xcodeproj/project.pbxproj \
  "PRODUCT_BUNDLE_IDENTIFIER = com.zlichtman.heartable;"
require_literal Heartable.xcodeproj/project.pbxproj \
  "PRODUCT_BUNDLE_IDENTIFIER = com.zlichtman.heartable.widget;"

test -f "$ROOT/Heartable.xcodeproj/xcshareddata/xcschemes/Heartable.xcscheme" ||
  fail "shared Heartable scheme is missing"

# Xcode Cloud clones through an Apple-managed internal remote even though the
# workflow is bound to the canonical GitHub repository. Keep the local guard
# strict, while avoiding a false failure inside that trusted CI environment.
if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ] && [ "${CI_XCODE_CLOUD:-}" != "1" ]; then
  remote="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
  case "$remote" in
    https://github.com/zlichtman/Heartable|https://github.com/zlichtman/Heartable.git|git@github.com:zlichtman/Heartable.git)
      ;;
    *)
      fail "origin is not zlichtman/Heartable"
      ;;
  esac
fi

legacy_brand="$(printf '%s%s' 'Lovi' 'fy')"
legacy_path="$(printf '%s%s' 'Heartable' '-Dev')"
if git -C "$ROOT" grep -I -n -E "$legacy_brand|$legacy_path" -- \
  . ':!ci_scripts/validate_release_identity.sh'
then
  fail "tracked legacy product identity remains"
fi

echo "release identity check passed"

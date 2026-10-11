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
require_literal Heartable/Resources/Heartable.entitlements \
  "com.apple.developer.applesignin"
require_literal Heartable/Resources/Info.plist \
  "NSAppleMusicUsageDescription"
require_literal Heartable/Resources/Info.plist \
  "NSCameraUsageDescription"
require_literal Heartable/Resources/Info.plist \
  "NSLocalNetworkUsageDescription"
require_literal Heartable/Resources/PrivacyInfo.xcprivacy \
  "NSPrivacyAccessedAPICategoryUserDefaults"
require_literal Heartable/Resources/PrivacyInfo.xcprivacy \
  "CA92.1"
require_literal Heartable/Resources/PrivacyInfo.xcprivacy \
  "NSPrivacyAccessedAPICategoryFileTimestamp"
require_literal Heartable/Resources/PrivacyInfo.xcprivacy \
  "C617.1"
require_literal Heartable.xcodeproj/project.pbxproj \
  "PRODUCT_BUNDLE_IDENTIFIER = com.zlichtman.heartable;"

# Retired surfaces (home-screen widget, App Group, contact discovery) must not
# quietly return through the project spec, entitlements, or Info.plist.
if grep -Fq "com.apple.security.application-groups" "$ROOT/Heartable/Resources/Heartable.entitlements"; then
  fail "Heartable.entitlements still declares an App Group"
fi
if grep -Fq "NSContactsUsageDescription" "$ROOT/Heartable/Resources/Info.plist"; then
  fail "Info.plist still declares contacts access"
fi
if grep -Fq "com.zlichtman.heartable.widget" "$ROOT/project.yml"; then
  fail "project.yml still declares the widget extension"
fi

test -f "$ROOT/Heartable.xcodeproj/xcshareddata/xcschemes/Heartable.xcscheme" ||
  fail "shared Heartable scheme is missing"

for plist in \
  Heartable/Resources/Info.plist \
  Heartable/Resources/Heartable.entitlements \
  Heartable/Resources/PrivacyInfo.xcprivacy
do
  plutil -lint "$ROOT/$plist" >/dev/null || fail "$plist is not a valid property list"
done

# Private signing material and server-side credentials must never enter the
# public repository. Public client identifiers and Supabase publishable/anon
# keys are intentionally excluded from this filename-level guard.
if git -C "$ROOT" ls-files | grep -E \
  '(^|/)(\.env($|\.)|[^/]+\.(p8|p12|mobileprovision|cer|key)$)'
then
  fail "tracked private key, provisioning profile, certificate, or env file found"
fi

if git -C "$ROOT" grep -I -n -E \
  'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|sb_secret_' -- \
  . ':!ci_scripts/validate_release_identity.sh'
then
  fail "tracked private key or Supabase secret key content found"
fi

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

echo "release identity check passed"

#!/usr/bin/env bash
#
# Assert that the version numbers this package hand-maintains in several
# places actually agree. Nothing else checks them: a release is cut by
# tagging, and a tag does not read pubspec.yaml.
#
# Checked:
#   1. The wrapper's own version:
#        pubspec.yaml                  version: X.Y.Z    (what pub.dev serves)
#        android/build.gradle          version = "X.Y.Z" (the AAR Gradle builds)
#        ios/issuetracker_sdk.podspec  s.version = 'X.Y.Z'
#        the git tag, when one is passed in (the publish workflow does)
#   2. The native SDK it bridges to. Android and iOS must pin the *same*
#      native version, exactly — a range on one side lets a single release
#      of this wrapper bridge to different native SDKs per platform.
#
# Usage:
#   tool/check_versions.sh          # the three files must agree
#   tool/check_versions.sh 0.6.0    # ...and must equal this tag
#
set -euo pipefail
cd "$(dirname "$0")/.."

status=0

fail() {
  # ::error:: makes the line show up as an annotation on the GitHub run.
  echo "::error::$*" >&2
  status=1
}

# Extract with sed, then insist the result is non-empty. A renamed field
# must fail loudly rather than compare "" against "" and pass.
#
# extract() only PRINTS and RETURNS; it must never record the failure
# itself. Every call site is a command substitution, which runs in a
# subshell, so a `status=1` executed in here would be assigned in that
# subshell and discarded — the script would then compare "" against ""
# and exit 0 while having read nothing. That is the exact defect this
# file exists to prevent, so the bookkeeping lives in the caller:
# read_field() below is the only sanctioned way to invoke it.
extract() {
  local description="$1" file="$2" expression="$3" value
  if [ ! -f "$file" ]; then
    echo "::error::$file does not exist (has it been moved or renamed?)" >&2
    return 1
  fi
  value=$(sed -n "$expression" "$file" | head -1)
  if [ -z "$value" ]; then
    echo "::error::could not read $description from $file (has the field been renamed?)" >&2
    return 1
  fi
  printf '%s' "$value"
}

# read_field VARNAME description file sed-expression
#
# Assigns the extracted value to VARNAME in THIS shell and records a
# failure here, in the parent, when extraction fails. The `if !` guard
# is what keeps `set -e` from aborting mid-run: we want every unreadable
# field reported in one pass, not just the first.
read_field() {
  local varname="$1" value
  shift
  if value=$(extract "$@"); then
    printf -v "$varname" '%s' "$value"
  else
    printf -v "$varname" '%s' ''
    status=1
  fi
}

read_field pubspec_version "version" pubspec.yaml \
  's/^version:[[:space:]]*\([^[:space:]]*\).*/\1/p'
read_field gradle_version "version" android/build.gradle \
  's/^version[[:space:]]*=[[:space:]]*"\([^"]*\)".*/\1/p'
read_field podspec_version "s.version" ios/issuetracker_sdk.podspec \
  "s/.*s\.version[[:space:]]*=[[:space:]]*'\([^']*\)'.*/\1/p"

if [ "$pubspec_version" != "$gradle_version" ]; then
  fail "pubspec.yaml version '$pubspec_version' != android/build.gradle version '$gradle_version'"
fi
if [ "$pubspec_version" != "$podspec_version" ]; then
  fail "pubspec.yaml version '$pubspec_version' != podspec s.version '$podspec_version'"
fi

if [ "$#" -ge 1 ]; then
  tag="$1"
  if [ "$tag" != "$pubspec_version" ]; then
    fail "tag '$tag' does not match pubspec.yaml version '$pubspec_version'"
  fi
fi

# --- native dependency pins ------------------------------------------------

read_field gradle_native "no.issuetracker:sdk pin" android/build.gradle \
  's/.*implementation("no\.issuetracker:sdk:\([^"]*\)").*/\1/p'
read_field podspec_native "IssuetrackerSDK pin" ios/issuetracker_sdk.podspec \
  "s/.*s\.dependency 'IssuetrackerSDK',[[:space:]]*'\([^']*\)'.*/\1/p"

case "$podspec_native" in
  *'~>'*|*'>'*|*'<'*|*' '*)
    fail "podspec pins IssuetrackerSDK to the range '$podspec_native'; pin an exact version so both platforms bridge to the same native SDK"
    ;;
esac

if [ "$gradle_native" != "$podspec_native" ]; then
  fail "native SDK pins differ: Android 'no.issuetracker:sdk:$gradle_native' vs iOS 'IssuetrackerSDK $podspec_native'"
fi

# Backstop. Nothing below may print the success line while any field is
# empty: an empty value means a comparison above compared "" against ""
# and "passed" without reading anything. read_field already sets status
# for that case; this catches a future edit that adds a field and
# forgets to route it through read_field.
for pair in \
  "pubspec.yaml version:$pubspec_version" \
  "android/build.gradle version:$gradle_version" \
  "podspec s.version:$podspec_version" \
  "android/build.gradle no.issuetracker:sdk pin:$gradle_native" \
  "podspec IssuetrackerSDK pin:$podspec_native"
do
  if [ -z "${pair##*:}" ]; then
    fail "no value was read for ${pair%:*} — refusing to report consistency on unread fields"
  fi
done

if [ "$status" -eq 0 ]; then
  echo "version $pubspec_version consistent (pubspec, gradle, podspec${1:+, tag}); native SDK pinned to $gradle_native on both platforms"
fi

exit "$status"

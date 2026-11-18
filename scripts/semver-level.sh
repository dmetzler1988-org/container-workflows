#!/bin/sh
# Decides whether a new build is a release, and at which SemVer level.
#
# Usage:
#   semver-level.sh LOCK_FILE STATE_JSON FILES_CHANGED OVERRIDE
#
#   LOCK_FILE      versions.lock of the last release. A missing file means "no release yet".
#   STATE_JSON     the new build, same shape as the lock without "version":
#                  {"base": {"image", "digest", "alpineVersion"},
#                   "images": {KEY: {"upstreamVersion", "packages": {PLATFORM: SHA256}}}}
#   FILES_CHANGED  true when release-relevant files changed since the last release tag
#   OVERRIDE       none|patch|minor|major; raises the computed level, never lowers it
#
# Rules, the highest level wins:
#   major  an image key was removed
#   minor  an image key was added, or the base Alpine minor version changed (3.24 -> 3.25)
#   patch  an upstream version, the base digest or Alpine patch version, a package list, or release files changed
#
# Prints key=value lines on stdout:
#   level    none|initial|patch|minor|major
#   version  the version to release, or the current version when level is none
#   reason   short human-readable explanation
#
# Exit codes: 0 ok, 2 invalid argument, 3 invalid lock file.
set -eu

readonly INITIAL_VERSION=1.0.0
readonly EXIT_USAGE=2
readonly EXIT_LOCK=3

usage_error() {
  echo "semver-level: $*" >&2
  exit "$EXIT_USAGE"
}

lock_error() {
  echo "semver-level: $*" >&2
  exit "$EXIT_LOCK"
}

level_rank() {
  case "$1" in
    none) echo 0 ;;
    patch) echo 1 ;;
    minor) echo 2 ;;
    major) echo 3 ;;
    *) usage_error "unknown level '$1'" ;;
  esac
}

is_semver() {
  printf '%s' "$1" | grep -Eq '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
}

bump() {
  version=$1
  level=$2
  major=${version%%.*}
  rest=${version#*.}
  minor=${rest%%.*}
  patch=${rest#*.}
  case "$level" in
    major) echo "$((major + 1)).0.0" ;;
    minor) echo "$major.$((minor + 1)).0" ;;
    patch) echo "$major.$minor.$((patch + 1))" ;;
    *) echo "$version" ;;
  esac
}

if [ "$#" -ne 4 ]; then
  usage_error "expected 4 arguments, got $#"
fi

lock_file=$1
state_json=$2
files_changed=$3
override=$4

case "$files_changed" in
  true | false) ;;
  *) usage_error "FILES_CHANGED must be true or false, got '$files_changed'" ;;
esac
override_rank=$(level_rank "$override")
if ! state=$(printf '%s' "$state_json" | jq -S -c '
    if (.base | type) == "object" and (.images | type) == "object" and (.images | length) > 0
    then . else error("bad shape") end' 2>/dev/null); then
  usage_error "STATE_JSON must be an object with a base object and a non-empty images object"
fi
new_alpine=$(printf '%s' "$state" | jq -r '.base.alpineVersion // ""')
if ! is_semver "$new_alpine"; then
  usage_error "base.alpineVersion must look like 3.24.4, got '$new_alpine'"
fi

if [ ! -e "$lock_file" ]; then
  echo "level=initial"
  echo "version=$INITIAL_VERSION"
  echo "reason=first release"
  exit 0
fi

if ! old_version=$(jq -er '.version' "$lock_file" 2>/dev/null); then
  lock_error "$lock_file has no readable .version"
fi
if ! is_semver "$old_version"; then
  lock_error "$lock_file has an invalid version '$old_version'"
fi
if ! jq -e '(.images | type) == "object"' "$lock_file" > /dev/null 2>&1; then
  lock_error "$lock_file is in the v1 format; convert it with convert-lock-v1.sh first"
fi
old=$(jq -S -c 'del(.version)' "$lock_file")

# One jq program computes the level and the reason from old and new state.
result=$(jq -n -r --argjson old "$old" --argjson new "$state" --arg files "$files_changed" '
  def minor_of: split(".")[0:2] | join(".");
  ($old.images | keys) as $old_keys
  | ($new.images | keys) as $new_keys
  | ($old_keys - $new_keys) as $removed
  | ($new_keys - $old_keys) as $added
  | [$new_keys[] | select(($old_keys | index(.)) != null)] as $kept
  | [$kept[] | select($old.images[.].upstreamVersion != $new.images[.].upstreamVersion)] as $upstream
  | [$kept[] | select(($old.images[.].packages // {}) != ($new.images[.].packages // {}))] as $packages
  | ($old.base.alpineVersion // "") as $old_alpine
  | ($new.base.alpineVersion) as $new_alpine
  | if ($removed | length) > 0 then "major\timage removed: \($removed | join(", "))"
    elif ($added | length) > 0 then "minor\timage added: \($added | join(", "))"
    elif ($old_alpine | minor_of) != ($new_alpine | minor_of) then "minor\tAlpine \($old_alpine) -> \($new_alpine)"
    elif ($upstream | length) > 0 then
      "patch\tupstream update: \([$upstream[] | "\(.) \($old.images[.].upstreamVersion) -> \($new.images[.].upstreamVersion)"] | join(", "))"
    elif $old_alpine != $new_alpine then "patch\tAlpine \($old_alpine) -> \($new_alpine)"
    elif ($old.base.digest // "") != ($new.base.digest // "") then "patch\tnew base image digest"
    elif ($packages | length) > 0 then "patch\tinstalled packages changed: \($packages | join(", "))"
    elif $files == "true" then "patch\timage files changed"
    else "none\tno changes"
    end')
computed=${result%%"	"*}
reason=${result#*"	"}

level=$computed
if [ "$override_rank" -gt "$(level_rank "$computed")" ]; then
  level=$override
  reason="$reason; raised to $override by request"
fi

echo "level=$level"
echo "version=$(bump "$old_version" "$level")"
echo "reason=$reason"

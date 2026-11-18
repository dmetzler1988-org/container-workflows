#!/bin/sh
# Decides whether a new image build is a release, and at which SemVer level.
#
# Usage:
#   semver-level.sh LOCK_FILE ALPINE_VERSION ALPINE_DIGEST PACKAGES_JSON FILES_CHANGED OVERRIDE
#
#   LOCK_FILE       versions.lock of the last release. A missing file means "no release yet".
#   ALPINE_VERSION  Alpine version inside the new build, e.g. 3.24.4
#   ALPINE_DIGEST   digest of the upstream alpine image the build used
#   PACKAGES_JSON   JSON object, platform -> sha256 of the installed package list
#   FILES_CHANGED   true when release-relevant files changed since the last release tag
#   OVERRIDE        none|patch|minor|major; raises the computed level, never lowers it
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

if [ "$#" -ne 6 ]; then
  usage_error "expected 6 arguments, got $#"
fi

lock_file=$1
alpine_version=$2
alpine_digest=$3
packages_json=$4
files_changed=$5
override=$6

case "$files_changed" in
  true | false) ;;
  *) usage_error "FILES_CHANGED must be true or false, got '$files_changed'" ;;
esac
override_rank=$(level_rank "$override")
if ! is_semver "$alpine_version"; then
  usage_error "ALPINE_VERSION must look like 3.24.4, got '$alpine_version'"
fi
if ! new_packages=$(printf '%s' "$packages_json" | jq -S -c 'if type == "object" then . else error("not an object") end' 2>/dev/null); then
  usage_error "PACKAGES_JSON must be a JSON object"
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
old_alpine_version=$(jq -r '.alpineVersion // ""' "$lock_file")
old_alpine_digest=$(jq -r '.alpineDigest // ""' "$lock_file")
old_packages=$(jq -S -c '.packages // {}' "$lock_file")

computed="none"
reason="no changes"
if [ "${old_alpine_version%.*}" != "${alpine_version%.*}" ]; then
  computed="minor"
  reason="Alpine $old_alpine_version -> $alpine_version"
elif [ "$old_alpine_version" != "$alpine_version" ]; then
  computed="patch"
  reason="Alpine $old_alpine_version -> $alpine_version"
elif [ "$old_alpine_digest" != "$alpine_digest" ]; then
  computed="patch"
  reason="new upstream alpine image digest"
elif [ "$old_packages" != "$new_packages" ]; then
  computed="patch"
  reason="installed packages changed"
elif [ "$files_changed" = true ]; then
  computed="patch"
  reason="image files changed"
fi

level=$computed
if [ "$override_rank" -gt "$(level_rank "$computed")" ]; then
  level=$override
  reason="$reason; raised to $override by request"
fi

echo "level=$level"
echo "version=$(bump "$old_version" "$level")"
echo "reason=$reason"

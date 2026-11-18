#!/bin/sh
# Prints the tags one image gets in a release, one per line. The first line is the immutable tag.
#
# Usage:
#   compute-tags.sh UPSTREAM_VERSION TAG_SUFFIX SEMVER MAJOR_TAG LATEST
#
#   UPSTREAM_VERSION  e.g. 3.14.10 (Python) or 3.24.4 (Alpine)
#   TAG_SUFFIX        e.g. -dev, or empty
#   SEMVER            the release version, e.g. 1.4.2
#   MAJOR_TAG         true|false: also tag <major><suffix>, e.g. 3-dev. Only the top version line sets it.
#   LATEST            true|false: also tag latest. Only the top line's runtime image sets it.
#
# Output for 3.14.10 -dev 1.4.2 true false:
#   3.14.10-dev-1.4.2
#   3.14.10-dev
#   3.14-dev
#   3-dev
#
# Exit codes: 0 ok, 2 invalid argument.
set -eu

readonly EXIT_USAGE=2

usage_error() {
  echo "compute-tags: $*" >&2
  exit "$EXIT_USAGE"
}

is_bool() {
  [ "$1" = true ] || [ "$1" = false ]
}

if [ "$#" -ne 5 ]; then
  usage_error "expected 5 arguments, got $#"
fi
upstream=$1
suffix=$2
semver=$3
major_tag=$4
latest=$5

if ! printf '%s' "$upstream" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  usage_error "UPSTREAM_VERSION must look like 3.14.10, got '$upstream'"
fi
if ! printf '%s' "$semver" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  usage_error "SEMVER must look like 1.4.2, got '$semver'"
fi
# grep sees no line at all for an empty suffix, so an empty suffix is accepted separately.
if [ -n "$suffix" ] && ! printf '%s\n' "$suffix" | grep -Eq '^-[a-z0-9]+$'; then
  usage_error "TAG_SUFFIX must be empty or look like -dev, got '$suffix'"
fi
if ! is_bool "$major_tag" || ! is_bool "$latest"; then
  usage_error "MAJOR_TAG and LATEST must be true or false"
fi

echo "$upstream$suffix-$semver"
echo "$upstream$suffix"
echo "${upstream%.*}$suffix"
if [ "$major_tag" = true ]; then
  echo "${upstream%%.*}$suffix"
fi
if [ "$latest" = true ]; then
  echo "latest"
fi

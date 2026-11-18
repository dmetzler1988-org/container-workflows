#!/bin/sh
# Prints facts about an Alpine-based image as key=value lines:
#   alpine-version   content of /etc/alpine-release, e.g. 3.24.4
#   packages-sha256  sha256 of the sorted "name-version" list from apk's package database
#
# Reads /lib/apk/db/installed directly, so it also works on images where `finalize` removed apk.
#
# Usage: image-facts.sh IMAGE
# Exit codes: 0 ok, 2 missing argument, 1 image unreadable.
set -eu

readonly EXIT_USAGE=2
readonly APK_DB=/lib/apk/db/installed

if [ "$#" -ne 1 ]; then
  echo "image-facts: usage: image-facts.sh IMAGE" >&2
  exit "$EXIT_USAGE"
fi
image=$1

alpine_version=$(docker run --rm --user 0 --entrypoint /bin/cat "$image" /etc/alpine-release)
packages_sha256=$(docker run --rm --user 0 --entrypoint /bin/sh "$image" -c \
  "awk '/^P:/ { name = substr(\$0, 3) } /^V:/ { print name \"-\" substr(\$0, 3) }' $APK_DB | sort | sha256sum | cut -d ' ' -f 1")

echo "alpine-version=$alpine_version"
echo "packages-sha256=$packages_sha256"

#!/bin/sh
# Prints facts about an Alpine-based image as key=value lines:
#   alpine-version    content of /etc/alpine-release, e.g. 3.24.4
#   packages-sha256   sha256 of the sorted "name-version" list from apk's package database
#   upstream-version  output of VERSION_COMMAND run in the image (default: the Alpine version)
#
# Reads /lib/apk/db/installed directly, so it also works on images where `finalize` removed apk.
#
# Usage: image-facts.sh IMAGE [VERSION_COMMAND]
#   VERSION_COMMAND  shell command run inside the image that prints the upstream version,
#                    e.g. "python3 -c 'import platform; print(platform.python_version())'"
# Exit codes: 0 ok, 2 wrong arguments, 1 image unreadable.
set -eu

readonly EXIT_USAGE=2
readonly APK_DB=/lib/apk/db/installed
readonly DEFAULT_VERSION_COMMAND="cat /etc/alpine-release"

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
  echo "image-facts: usage: image-facts.sh IMAGE [VERSION_COMMAND]" >&2
  exit "$EXIT_USAGE"
fi
image=$1
version_command=${2:-$DEFAULT_VERSION_COMMAND}

alpine_version=$(docker run --rm --user 0 --entrypoint /bin/cat "$image" /etc/alpine-release)
packages_sha256=$(docker run --rm --user 0 --entrypoint /bin/sh "$image" -c \
  "awk '/^P:/ { name = substr(\$0, 3) } /^V:/ { print name \"-\" substr(\$0, 3) }' $APK_DB | sort | sha256sum | cut -d ' ' -f 1")
upstream_version=$(docker run --rm --entrypoint /bin/sh "$image" -c "$version_command")

echo "alpine-version=$alpine_version"
echo "packages-sha256=$packages_sha256"
echo "upstream-version=$upstream_version"

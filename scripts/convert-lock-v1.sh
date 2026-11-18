#!/bin/sh
# Converts a v1 versions.lock (single Alpine image) to the v2 format and prints it. One-time migration.
#
# Usage: convert-lock-v1.sh LOCK_FILE IMAGE_KEY BASE_IMAGE
#   LOCK_FILE   the v1 lock: {version, alpineVersion, alpineDigest, packages}
#   IMAGE_KEY   key of the single image in v2, e.g. alpine
#   BASE_IMAGE  base image reference to record, e.g. docker.io/library/alpine:3.24
#
# The version stays the same, so the next release continues the series.
# Exit codes: 0 ok, 2 invalid argument, 3 not a v1 lock.
set -eu

readonly EXIT_USAGE=2
readonly EXIT_LOCK=3

if [ "$#" -ne 3 ]; then
  echo "convert-lock-v1: expected 3 arguments, got $#" >&2
  exit "$EXIT_USAGE"
fi
lock_file=$1
image_key=$2
base_image=$3

if ! jq -e '(.version | type) == "string" and (.alpineVersion | type) == "string" and (.images == null)' "$lock_file" > /dev/null 2>&1; then
  echo "convert-lock-v1: $lock_file is not a v1 lock" >&2
  exit "$EXIT_LOCK"
fi

jq --arg key "$image_key" --arg base "$base_image" '{
  version: .version,
  base: {image: $base, digest: .alpineDigest, alpineVersion: .alpineVersion},
  images: {($key): {upstreamVersion: .alpineVersion, packages: .packages}}
}' "$lock_file"

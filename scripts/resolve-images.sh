#!/bin/sh
# Gives every entry of release.yaml's image list the package it is published to, and prints the list as JSON.
#
# Usage:
#   resolve-images.sh DEFAULT_IMAGE IMAGES_JSON
#
#   DEFAULT_IMAGE  e.g. ghcr.io/owner/python-minimal; used for every entry without its own "image". May be empty
#                  when every entry has one.
#   IMAGES_JSON    the list given to release.yaml, e.g. [{"key": "8.6-fpm", "image": "ghcr.io/owner/php-fpm-minimal"}]
#
# Exit codes: 0 ok, 2 invalid argument or an entry left without an image name.
set -eu

readonly EXIT_USAGE=2

usage_error() {
  echo "resolve-images: $*" >&2
  exit "$EXIT_USAGE"
}

if [ "$#" -ne 2 ]; then
  usage_error "expected 2 arguments, got $#"
fi
default_image=$1
images=$2

resolved=$(printf '%s' "$images" | jq -c --arg image "$default_image" \
  'map(.image = ((.image // "") | if . == "" then $image else . end))') \
  || usage_error "IMAGES_JSON is not a JSON list"
missing=$(printf '%s' "$resolved" | jq -r '[.[] | select(.image == "") | .key] | join(", ")')
if [ -n "$missing" ]; then
  usage_error "$missing has no image name (set inputs.image or the entry's own \"image\")"
fi
printf '%s\n' "$resolved"

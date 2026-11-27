#!/bin/sh
# Prints the newest published, non-prerelease patch version of an upstream version line.
#
# Usage: upstream-latest.sh KIND LINE
#   KIND  python | php
#   LINE  e.g. 3.14 or 8.6
#
# Environment:
#   UPSTREAM_JSON_FILE  read the upstream answer from this file instead of the network (tests)
#
# Exit codes: 0 ok, 1 no release found or download failed, 2 invalid argument.
set -eu

readonly EXIT_USAGE=2
readonly PYTHON_RELEASES_URL="https://www.python.org/api/v2/downloads/release/?is_published=true&pre_release=false"
readonly PHP_RELEASES_URL="https://www.php.net/releases/index.php?json&version="
readonly CONNECT_TIMEOUT_SECONDS=10
readonly MAX_TIME_SECONDS=60

fetch() {
  if [ -n "${UPSTREAM_JSON_FILE:-}" ]; then
    cat "$UPSTREAM_JSON_FILE"
    return
  fi
  curl -fsS --retry 3 --connect-timeout "$CONNECT_TIMEOUT_SECONDS" --max-time "$MAX_TIME_SECONDS" "$1"
}

if [ "$#" -ne 2 ]; then
  echo "upstream-latest: expected 2 arguments, got $#" >&2
  exit "$EXIT_USAGE"
fi
kind=$1
line=$2

if ! printf '%s\n' "$line" | grep -Eq '^[0-9]+\.[0-9]+$'; then
  echo "upstream-latest: LINE must look like 3.14, got '$line'" >&2
  exit "$EXIT_USAGE"
fi

case "$kind" in
  python)
    answer=$(fetch "$PYTHON_RELEASES_URL")
    latest=$(printf '%s' "$answer" | jq -r --arg line "$line" '
      [.[] | .name | capture("^Python (?<v>[0-9]+\\.[0-9]+\\.[0-9]+)$")? | .v
           | select(startswith($line + "."))]
      | sort_by(split(".") | map(tonumber)) | last // empty')
    ;;
  php)
    answer=$(fetch "$PHP_RELEASES_URL$line")
    # php.net answers an unknown line with HTTP 200 and {"error": "Unknown version"}, so check the content.
    latest=$(printf '%s' "$answer" | jq -r --arg line "$line" '
      .version // empty | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+$") and startswith($line + "."))')
    ;;
  *)
    echo "upstream-latest: unknown KIND '$kind'" >&2
    exit "$EXIT_USAGE"
    ;;
esac

if [ -z "$latest" ]; then
  echo "upstream-latest: no published $kind $line release found" >&2
  exit 1
fi
echo "$latest"

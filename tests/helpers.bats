#!/usr/bin/env bats

SCRIPTS="$BATS_TEST_DIRNAME/../scripts"

# compute-tags.sh

@test "compute-tags: top runtime image gets major tag and latest" {
  run sh "$SCRIPTS/compute-tags.sh" 3.24.4 "" 1.0.2 true true
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '3.24.4-1.0.2\n3.24.4\n3.24\n3\nlatest')" ]
}

@test "compute-tags: top dev image gets major tag but no latest" {
  run sh "$SCRIPTS/compute-tags.sh" 3.14.10 -dev 1.4.2 true false
  [ "$output" = "$(printf '3.14.10-dev-1.4.2\n3.14.10-dev\n3.14-dev\n3-dev')" ]
}

@test "compute-tags: lower line gets neither major tag nor latest" {
  run sh "$SCRIPTS/compute-tags.sh" 3.13.18 "" 1.4.2 false false
  [ "$output" = "$(printf '3.13.18-1.4.2\n3.13.18\n3.13')" ]
}

@test "compute-tags: invalid suffix is rejected with exit 2" {
  run sh "$SCRIPTS/compute-tags.sh" 3.13.18 dev 1.4.2 false false
  [ "$status" -eq 2 ]
  [[ "$output" == *"TAG_SUFFIX must be empty or look like -dev"* ]]
}

@test "compute-tags: invalid flag is rejected with exit 2" {
  run sh "$SCRIPTS/compute-tags.sh" 3.13.18 "" 1.4.2 yes false
  [ "$status" -eq 2 ]
  [[ "$output" == *"must be true or false"* ]]
}

# convert-lock-v1.sh

@test "convert-lock-v1: keeps the version and maps every field" {
  printf '%s\n' '{"version": "1.0.1", "alpineVersion": "3.24.4", "alpineDigest": "sha256:aaaa", "packages": {"linux/amd64": "p1"}}' > "$BATS_TEST_TMPDIR/v1.lock"
  run sh "$SCRIPTS/convert-lock-v1.sh" "$BATS_TEST_TMPDIR/v1.lock" alpine docker.io/library/alpine:3.24
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -c .)" = '{"version":"1.0.1","base":{"image":"docker.io/library/alpine:3.24","digest":"sha256:aaaa","alpineVersion":"3.24.4"},"images":{"alpine":{"upstreamVersion":"3.24.4","packages":{"linux/amd64":"p1"}}}}' ]
}

@test "convert-lock-v1: refuses a v2 lock with exit 3" {
  printf '%s\n' '{"version": "1.0.1", "alpineVersion": "3.24.4", "images": {}}' > "$BATS_TEST_TMPDIR/v2.lock"
  run sh "$SCRIPTS/convert-lock-v1.sh" "$BATS_TEST_TMPDIR/v2.lock" alpine docker.io/library/alpine:3.24
  [ "$status" -eq 3 ]
  [[ "$output" == *"is not a v1 lock"* ]]
}

# upstream-latest.sh

setup_releases() {
  RELEASES="$BATS_TEST_TMPDIR/releases.json"
  printf '%s\n' '[
    {"name": "Python 3.14.9"}, {"name": "Python 3.14.10"}, {"name": "Python 3.14.2"},
    {"name": "Python 3.13.18"}, {"name": "Python 3.1.5"}, {"name": "Python 3.15.0a2"}
  ]' > "$RELEASES"
}

@test "upstream-latest: picks the highest patch numerically, not alphabetically" {
  setup_releases
  UPSTREAM_JSON_FILE="$RELEASES" run sh "$SCRIPTS/upstream-latest.sh" python 3.14
  [ "$status" -eq 0 ]
  [ "$output" = "3.14.10" ]
}

@test "upstream-latest: 3.1 does not match 3.13 or 3.14" {
  setup_releases
  UPSTREAM_JSON_FILE="$RELEASES" run sh "$SCRIPTS/upstream-latest.sh" python 3.1
  [ "$output" = "3.1.5" ]
}

@test "upstream-latest: pre-releases are ignored" {
  setup_releases
  UPSTREAM_JSON_FILE="$RELEASES" run sh "$SCRIPTS/upstream-latest.sh" python 3.15
  [ "$status" -eq 1 ]
  [[ "$output" == *"no published python 3.15 release found"* ]]
}

@test "upstream-latest: php returns the line's current version" {
  printf '%s\n' '{"announcement": true, "version": "8.6.0", "date": "19 Nov 2026"}' > "$BATS_TEST_TMPDIR/php.json"
  UPSTREAM_JSON_FILE="$BATS_TEST_TMPDIR/php.json" run sh "$SCRIPTS/upstream-latest.sh" php 8.6
  [ "$status" -eq 0 ]
  [ "$output" = "8.6.0" ]
}

@test "upstream-latest: php unknown line (HTTP 200 with an error object) fails" {
  printf '%s\n' '{"error": "Unknown version"}' > "$BATS_TEST_TMPDIR/php.json"
  UPSTREAM_JSON_FILE="$BATS_TEST_TMPDIR/php.json" run sh "$SCRIPTS/upstream-latest.sh" php 8.7
  [ "$status" -eq 1 ]
  [[ "$output" == *"no published php 8.7 release found"* ]]
}

@test "upstream-latest: php answer for another line is rejected" {
  printf '%s\n' '{"version": "8.5.13"}' > "$BATS_TEST_TMPDIR/php.json"
  UPSTREAM_JSON_FILE="$BATS_TEST_TMPDIR/php.json" run sh "$SCRIPTS/upstream-latest.sh" php 8.6
  [ "$status" -eq 1 ]
}

@test "upstream-latest: unknown kind is rejected with exit 2" {
  run sh "$SCRIPTS/upstream-latest.sh" ruby 3.4
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown KIND 'ruby'"* ]]
}

@test "upstream-latest: invalid line is rejected with exit 2" {
  run sh "$SCRIPTS/upstream-latest.sh" python 3
  [ "$status" -eq 2 ]
}

# resolve-images.sh

@test "resolve-images: entries without image get the default" {
  run sh "$SCRIPTS/resolve-images.sh" ghcr.io/o/python-minimal '[{"key":"3.14"},{"key":"3.13","image":""}]'
  [ "$status" -eq 0 ]
  [ "$output" = '[{"key":"3.14","image":"ghcr.io/o/python-minimal"},{"key":"3.13","image":"ghcr.io/o/python-minimal"}]' ]
}

@test "resolve-images: an entry's own image wins over the default" {
  run sh "$SCRIPTS/resolve-images.sh" ghcr.io/o/php-minimal '[{"key":"8.6-fpm","image":"ghcr.io/o/php-fpm-minimal"}]'
  [ "$status" -eq 0 ]
  [ "$output" = '[{"key":"8.6-fpm","image":"ghcr.io/o/php-fpm-minimal"}]' ]
}

@test "resolve-images: no default needed when every entry has its own image" {
  run sh "$SCRIPTS/resolve-images.sh" "" '[{"key":"8.6-cli","image":"ghcr.io/o/php-cli-minimal"}]'
  [ "$status" -eq 0 ]
  [ "$output" = '[{"key":"8.6-cli","image":"ghcr.io/o/php-cli-minimal"}]' ]
}

@test "resolve-images: an entry left without any image is rejected with exit 2" {
  run sh "$SCRIPTS/resolve-images.sh" "" '[{"key":"8.6-cli","image":"ghcr.io/o/php-cli-minimal"},{"key":"8.5-cli"}]'
  [ "$status" -eq 2 ]
  [[ "$output" == *"8.5-cli has no image name"* ]]
}

@test "resolve-images: wrong argument count is rejected with exit 2" {
  run sh "$SCRIPTS/resolve-images.sh" ghcr.io/o/x
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected 2 arguments"* ]]
}

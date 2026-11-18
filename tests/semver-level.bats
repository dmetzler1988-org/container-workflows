#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/semver-level.sh"
DIGEST="sha256:aaaa"
PACKAGES='{"linux/amd64":"p1","linux/arm64":"p2"}'

setup() {
  LOCK="$BATS_TEST_TMPDIR/versions.lock"
  cat > "$LOCK" <<'JSON'
{
  "version": "1.2.3",
  "alpineVersion": "3.24.4",
  "alpineDigest": "sha256:aaaa",
  "packages": {
    "linux/arm64": "p2",
    "linux/amd64": "p1"
  }
}
JSON
}

@test "no lock file gives the initial release 1.0.0" {
  run sh "$SCRIPT" "$BATS_TEST_TMPDIR/missing.lock" 3.24.4 "$DIGEST" "$PACKAGES" false none
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "level=initial" ]
  [ "${lines[1]}" = "version=1.0.0" ]
}

@test "identical build gives no release, key order in packages does not matter" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" "$PACKAGES" false none
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "level=none" ]
  [ "${lines[1]}" = "version=1.2.3" ]
}

@test "changed package list gives a patch release" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" '{"linux/amd64":"p9","linux/arm64":"p2"}' false none
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[1]}" = "version=1.2.4" ]
}

@test "new upstream digest gives a patch release" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "sha256:bbbb" "$PACKAGES" false none
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[1]}" = "version=1.2.4" ]
}

@test "Alpine patch update gives a patch release" {
  run sh "$SCRIPT" "$LOCK" 3.24.5 "sha256:bbbb" "$PACKAGES" false none
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[1]}" = "version=1.2.4" ]
}

@test "Alpine minor update gives a minor release" {
  run sh "$SCRIPT" "$LOCK" 3.25.0 "sha256:bbbb" "$PACKAGES" false none
  [ "${lines[0]}" = "level=minor" ]
  [ "${lines[1]}" = "version=1.3.0" ]
}

@test "changed image files give a patch release" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" "$PACKAGES" true none
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[1]}" = "version=1.2.4" ]
}

@test "override raises a patch to major" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" "$PACKAGES" true major
  [ "${lines[0]}" = "level=major" ]
  [ "${lines[1]}" = "version=2.0.0" ]
}

@test "override never lowers the computed level" {
  run sh "$SCRIPT" "$LOCK" 3.25.0 "$DIGEST" "$PACKAGES" false patch
  [ "${lines[0]}" = "level=minor" ]
  [ "${lines[1]}" = "version=1.3.0" ]
}

@test "override forces a release when nothing changed" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" "$PACKAGES" false patch
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[1]}" = "version=1.2.4" ]
}

@test "unknown override is rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" "$PACKAGES" false huge
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown level 'huge'"* ]]
}

@test "packages that are not a JSON object are rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" '["p1"]' false none
  [ "$status" -eq 2 ]
  [[ "$output" == *"PACKAGES_JSON must be a JSON object"* ]]
}

@test "invalid Alpine version is rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK" 3.24 "$DIGEST" "$PACKAGES" false none
  [ "$status" -eq 2 ]
  [[ "$output" == *"ALPINE_VERSION must look like 3.24.4"* ]]
}

@test "lock with an invalid version is rejected with exit 3" {
  printf '{"version": "1.0"}\n' > "$LOCK"
  run sh "$SCRIPT" "$LOCK" 3.24.4 "$DIGEST" "$PACKAGES" false none
  [ "$status" -eq 3 ]
  [[ "$output" == *"invalid version '1.0'"* ]]
}

@test "wrong argument count is rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK" 3.24.4
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected 6 arguments, got 2"* ]]
}

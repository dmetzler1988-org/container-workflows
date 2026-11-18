#!/usr/bin/env bats

SCRIPT="$BATS_TEST_DIRNAME/../scripts/semver-level.sh"

# State equal to the lock written in setup(); tests change one thing at a time with jq.
STATE='{
  "base": {"image": "ghcr.io/o/alpine-minimal:3.24", "digest": "sha256:aaaa", "alpineVersion": "3.24.4"},
  "images": {
    "3.14": {"upstreamVersion": "3.14.10", "packages": {"linux/amd64": "p1", "linux/arm64": "p2"}},
    "3.14-dev": {"upstreamVersion": "3.14.10", "packages": {"linux/amd64": "d1", "linux/arm64": "d2"}}
  }
}'

state_with() {
  printf '%s' "$STATE" | jq -c "$1"
}

setup() {
  LOCK="$BATS_TEST_TMPDIR/versions.lock"
  printf '%s' "$STATE" | jq '{version: "1.2.3"} + .' > "$LOCK"
}

@test "no lock file gives the initial release 1.0.0" {
  run sh "$SCRIPT" "$BATS_TEST_TMPDIR/missing.lock" "$STATE" false none
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "level=initial" ]
  [ "${lines[1]}" = "version=1.0.0" ]
}

@test "identical build gives no release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.')" false none
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "level=none" ]
  [ "${lines[1]}" = "version=1.2.3" ]
}

@test "key order inside the state does not matter" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.images |= (to_entries | reverse | from_entries)')" false none
  [ "${lines[0]}" = "level=none" ]
}

@test "removed image gives a major release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with 'del(.images["3.14-dev"])')" false none
  [ "${lines[0]}" = "level=major" ]
  [ "${lines[1]}" = "version=2.0.0" ]
  [ "${lines[2]}" = "reason=image removed: 3.14-dev" ]
}

@test "added image gives a minor release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.images["3.13"] = {"upstreamVersion": "3.13.18", "packages": {}}')" false none
  [ "${lines[0]}" = "level=minor" ]
  [ "${lines[1]}" = "version=1.3.0" ]
}

@test "base Alpine minor update gives a minor release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.base.alpineVersion = "3.25.0" | .base.digest = "sha256:bbbb"')" false none
  [ "${lines[0]}" = "level=minor" ]
  [ "${lines[1]}" = "version=1.3.0" ]
}

@test "upstream patch update gives a patch release and names the image" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.images["3.14"].upstreamVersion = "3.14.11"')" false none
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[1]}" = "version=1.2.4" ]
  [ "${lines[2]}" = "reason=upstream update: 3.14 3.14.10 -> 3.14.11" ]
}

@test "base Alpine patch update gives a patch release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.base.alpineVersion = "3.24.5"')" false none
  [ "${lines[0]}" = "level=patch" ]
}

@test "new base digest gives a patch release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.base.digest = "sha256:bbbb"')" false none
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[2]}" = "reason=new base image digest" ]
}

@test "base image name alone does not cause a release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.base.image = "ghcr.io/o/alpine-minimal:3.24.4"')" false none
  [ "${lines[0]}" = "level=none" ]
}

@test "changed package list gives a patch release" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.images["3.14-dev"].packages["linux/arm64"] = "d9"')" false none
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[2]}" = "reason=installed packages changed: 3.14-dev" ]
}

@test "changed image files give a patch release" {
  run sh "$SCRIPT" "$LOCK" "$STATE" true none
  [ "${lines[0]}" = "level=patch" ]
}

@test "removal beats every other change" {
  run sh "$SCRIPT" "$LOCK" "$(state_with 'del(.images["3.14"]) | .base.alpineVersion = "3.25.0"')" true none
  [ "${lines[0]}" = "level=major" ]
}

@test "override raises a patch to major" {
  run sh "$SCRIPT" "$LOCK" "$STATE" true major
  [ "${lines[0]}" = "level=major" ]
  [ "${lines[1]}" = "version=2.0.0" ]
}

@test "override never lowers the computed level" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.base.alpineVersion = "3.25.0"')" false patch
  [ "${lines[0]}" = "level=minor" ]
}

@test "override forces a release when nothing changed" {
  run sh "$SCRIPT" "$LOCK" "$STATE" false patch
  [ "${lines[0]}" = "level=patch" ]
  [ "${lines[1]}" = "version=1.2.4" ]
}

@test "v1 lock is rejected with exit 3" {
  printf '{"version": "1.0.1", "alpineVersion": "3.24.4", "alpineDigest": "sha256:aaaa", "packages": {}}\n' > "$LOCK"
  run sh "$SCRIPT" "$LOCK" "$STATE" false none
  [ "$status" -eq 3 ]
  [[ "$output" == *"v1 format"* ]]
}

@test "lock with an invalid version is rejected with exit 3" {
  printf '{"version": "1.0", "images": {}}\n' > "$LOCK"
  run sh "$SCRIPT" "$LOCK" "$STATE" false none
  [ "$status" -eq 3 ]
  [[ "$output" == *"invalid version '1.0'"* ]]
}

@test "state without images is rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK" '{"base": {"alpineVersion": "3.24.4"}, "images": {}}' false none
  [ "$status" -eq 2 ]
  [[ "$output" == *"non-empty images object"* ]]
}

@test "invalid base Alpine version is rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK" "$(state_with '.base.alpineVersion = "3.24"')" false none
  [ "$status" -eq 2 ]
  [[ "$output" == *"must look like 3.24.4"* ]]
}

@test "unknown override is rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK" "$STATE" false huge
  [ "$status" -eq 2 ]
  [[ "$output" == *"unknown level 'huge'"* ]]
}

@test "wrong argument count is rejected with exit 2" {
  run sh "$SCRIPT" "$LOCK"
  [ "$status" -eq 2 ]
  [[ "$output" == *"expected 4 arguments, got 1"* ]]
}

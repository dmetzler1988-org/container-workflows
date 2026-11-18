# container-workflows

Reusable GitHub Actions workflows for the dmetzler1988-org container images. The image repositories hold
only their Dockerfile, tests and a few lines calling these workflows.

Call every workflow pinned by commit SHA, with the version as a comment. Dependabot keeps the pin current:

```yaml
uses: dmetzler1988-org/container-workflows/.github/workflows/build-image.yaml@<commit-sha> # v1.0.0
```

## Workflows

| Workflow | What it does |
|---|---|
| `build-image.yaml` | Builds on native amd64 and arm64 runners, runs the caller's test script, scans with Trivy (fails on fixable critical vulnerabilities, report to the Security tab), records the Alpine version and package list. Pushes nothing |
| `release.yaml` | Decides whether the build is a release and at which SemVer level, commits `versions.lock` and the git tag, then pushes, re-tests, tags, signs (cosign keyless) and attests (CycloneDX SBOM, vulnerability report) the image, and creates the GitHub Release |
| `rescan.yaml` | Scans an already published image again and reports to the Security tab |
| `dependabot-automerge.yaml` | Merges Dependabot's GitHub Actions updates. Call it after build and tests passed. Docker base updates are left for a human |

### build-image.yaml

| Input | Default | Meaning |
|---|---|---|
| `context` | `.` | Build context |
| `file` | `Dockerfile` | Dockerfile path |
| `build-contexts` | empty | Named build contexts, one per line. Used to pin the base image digest |
| `build-args` | empty | Build arguments, one per line |
| `test-script` | `tests/run.sh` | Executable test entry point; receives the image reference in `$IMAGE` |

Outputs: `alpine-version`, `packages-json` (platform to sha256 of the installed package list).

Caller job permissions: `contents: read`, `security-events: write`.

### release.yaml

Takes the same build inputs as `build-image.yaml` (the image is rebuilt from cache for the push and checked
against the tested package list), plus:

| Input | Default | Meaning |
|---|---|---|
| `image` | required | Image name without tag, e.g. `ghcr.io/dmetzler1988-org/alpine-minimal` |
| `alpine-version`, `packages-json` | required | Outputs of `build-image.yaml` |
| `alpine-digest` | required | Digest of the upstream alpine image the build was pinned to |
| `level` | `none` | Raises the computed level to at least `patch`, `minor` or `major` |
| `release-paths` | `Dockerfile rootfs` | Paths whose changes since the last release count as a patch |
| `tag-suffix` | empty | Appended to every tag, e.g. `-fpm` |
| `latest` | `true` | Also point `latest` at this release. Set it only for the top version line's runtime variant |

Caller job permissions: `contents: write`, `packages: write`, `id-token: write`.

How the level is chosen (`scripts/semver-level.sh`):

| Change since the last release | Level |
|---|---|
| No `versions.lock` yet | first release, `1.0.0` |
| Alpine minor version (3.24 to 3.25) | minor |
| Alpine patch version, upstream digest, installed packages, or files under `release-paths` | patch |
| Nothing | no release |

Tags per release, for Alpine 3.24.4 and version 1.0.1: `3.24.4`, `3.24`, `3` and `latest` (moving) and
`3.24.4-1.0.1` (immutable). The repository's default branch must accept pushes from `github-actions[bot]`, because the
release commit and tag are pushed with `GITHUB_TOKEN`.

### rescan.yaml

Input `image-ref`, e.g. `ghcr.io/dmetzler1988-org/alpine-minimal:3.24`. Caller job permissions:
`contents: read`, `security-events: write`.

### dependabot-automerge.yaml

No inputs. Caller job permissions: `contents: write`, `pull-requests: write`. Merges with `GITHUB_TOKEN`, so
the merge itself starts no new workflow run; the next scheduled build picks it up.

## Development

Everything runs in containers:

```sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.11.0 scripts/*.sh
docker run --rm -v "$PWD:/code" -w /code --entrypoint sh bats/bats:1.14.0 -c 'apk add --no-cache -q jq && bats tests'
```

## License

[GNU Affero General Public License v3](./LICENSE).

# container-workflows

Reusable GitHub Actions workflows for the dmetzler1988-org container images. The image repositories hold
only their Dockerfile, tests and a few lines calling these workflows.

Call every workflow pinned by commit SHA, with the version as a comment. Dependabot keeps the pin current:

```yaml
uses: dmetzler1988-org/container-workflows/.github/workflows/build-image.yaml@<commit-sha> # v2.0.0
```

## Workflows

| Workflow | What it does |
|---|---|
| `build-image.yaml` | Builds one image on native amd64 and arm64 runners, runs the caller's test script, scans with Trivy (fails on fixable critical vulnerabilities, report to the Security tab), records the image's facts. Pushes nothing. Call it once per image, in a matrix |
| `release.yaml` | One release for all images of a repository: decides whether the builds are a release and at which SemVer level, commits `versions.lock` and the git tag, then pushes, re-tests, tags, signs (cosign keyless) and attests (CycloneDX SBOM, vulnerability report) every image, and writes one GitHub Release |
| `rescan.yaml` | Scans an already published image again and reports to the Security tab |
| `dependabot-automerge.yaml` | Merges Dependabot's GitHub Actions updates. Call it after build and tests passed. Docker base updates are left for a human |

### build-image.yaml

| Input | Default | Meaning |
|---|---|---|
| `image-key` | required | Key of the image in `versions.lock`, e.g. `3.14-dev` or `alpine`. Letters, digits, dot and dash |
| `context` | `.` | Build context |
| `file` | `Dockerfile` | Dockerfile path |
| `target` | empty | Dockerfile stage; empty builds the last stage |
| `build-contexts` | empty | Named build contexts, one per line. Used to pin the base image digest |
| `build-args` | empty | Build arguments, one per line |
| `version-command` | `cat /etc/alpine-release` | Shell command run in the image that prints its upstream version |
| `test-script` | `tests/run.sh` | Executable test entry point; receives `$IMAGE` and `$IMAGE_KEY` |

Writes the artifact `facts__<image-key>__<arch>` for `release.yaml`. Caller job permissions:
`contents: read`, `security-events: write`.

### release.yaml

| Input | Default | Meaning |
|---|---|---|
| `image` | required | Image name without tag, e.g. `ghcr.io/dmetzler1988-org/python-minimal` |
| `images` | required | JSON list, one entry per image (below) |
| `base` | required | JSON `{"image", "digest", "alpineVersion"}` of the base image the builds were pinned to |
| `context`, `file`, `build-contexts`, `test-script` | as above | Same as given to `build-image.yaml`; each image is rebuilt from cache for the push and checked against the tested one |
| `level` | `none` | Raises the computed level to at least `patch`, `minor` or `major` |
| `release-paths` | `Dockerfile rootfs` | Paths whose changes since the last release count as a patch |
| `dry-run` | `false` | Decide and show version, tags and `versions.lock` in the run summary, write nothing |

One `images` entry:

| Field | Meaning |
|---|---|
| `key` | Same `image-key` as in `build-image.yaml` |
| `target`, `build-args`, `version-command` | Same as in `build-image.yaml` |
| `tag-suffix` | Appended to every tag of this image, e.g. `-dev` |
| `major-tag` | `true` adds the major tag, e.g. `3` or `3-dev`. Only for the top version line |
| `latest` | `true` adds `latest`. Only for the top line's runtime image |

Caller job permissions: `contents: write`, `packages: write`, `id-token: write`. The repository's default branch
must accept pushes from `github-actions[bot]`, because the release commit and tag are pushed with `GITHUB_TOKEN`.

Put `concurrency` on the job that calls `release.yaml`, not on the whole workflow, so frequent runs that build
nothing never cancel a waiting release.

How the level is chosen (`scripts/semver-level.sh`), the highest wins:

| Change since the last release | Level |
|---|---|
| No `versions.lock` yet | first release, `1.0.0` |
| An image removed | major |
| An image added, or the base Alpine minor version changed (3.24 to 3.25) | minor |
| An upstream version, the base digest or Alpine patch version, a package list, or files under `release-paths` | patch |
| Nothing | no release |

Tags per image (`scripts/compute-tags.sh`), for Python 3.14.10 and release 1.4.2:

| Image | Tags |
|---|---|
| `3.14` (`major-tag`, `latest`) | `3.14.10`, `3.14`, `3`, `latest`, immutable `3.14.10-1.4.2` |
| `3.14-dev` (`major-tag`) | `3.14.10-dev`, `3.14-dev`, `3-dev`, immutable `3.14.10-dev-1.4.2` |
| `3.13` | `3.13.18`, `3.13`, immutable `3.13.18-1.4.2` |

### versions.lock

Written only by `release.yaml`:

```json
{
  "version": "1.4.2",
  "base": { "image": "ghcr.io/dmetzler1988-org/alpine-minimal:3.24", "digest": "sha256:…", "alpineVersion": "3.24.4" },
  "images": {
    "3.14": { "upstreamVersion": "3.14.10", "packages": { "linux/amd64": "…", "linux/arm64": "…" } }
  }
}
```

`packages` holds the sha256 of each architecture's sorted package list. `base.image` is informational; only
`base.digest` and `base.alpineVersion` are compared.

### rescan.yaml

Input `image-ref`, e.g. `ghcr.io/dmetzler1988-org/alpine-minimal:3.24`. Caller job permissions:
`contents: read`, `security-events: write`.

### dependabot-automerge.yaml

No inputs. Caller job permissions: `contents: write`, `pull-requests: write`. Merges with `GITHUB_TOKEN`, so
the merge itself starts no new workflow run; the next scheduled build picks it up.

## Upgrading from v1

v2 is a breaking change:

- `build-image.yaml` needs `image-key` and has no workflow outputs anymore.
- `release.yaml` takes `images` and `base` instead of `alpine-version`, `alpine-digest`, `packages-json`,
  `tag-suffix` and `latest`.
- `versions.lock` has a new format. Convert it once, keeping the version:

```sh
sh scripts/convert-lock-v1.sh versions.lock alpine docker.io/library/alpine:3.24 > versions.lock.new
```

## Development

Everything runs in containers:

```sh
docker run --rm -v "$PWD:/repo" -w /repo rhysd/actionlint:1.7.12 -color
docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.11.0 scripts/*.sh
docker run --rm -v "$PWD:/code" -w /code --entrypoint sh bats/bats:1.14.0 -c 'apk add --no-cache -q jq && bats tests'
```

## License

[GNU Affero General Public License v3](./LICENSE).

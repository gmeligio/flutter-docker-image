## Approach

Two parts: a one-time ops fix (make the GHCR `flutter-android` package public)
and a permanent guardrail (`verify-published`) so the contract is self-enforcing.

### Why not automate the visibility flip

| Option | Verdict |
|---|---|
| **A. Manual flip only** | Fixes #492 today, but the next new image — or a re-created package — regresses silently. No guard. Rejected as incomplete. |
| **B. Manual flip + post-release anonymous smoke check** | Fixes today *and* makes the contract self-enforcing; surfaces Quay's unknown state. **Chosen.** |
| **C. Automate the flip in CI via PAT** | Requires a long-lived PAT with `write:packages` + admin as a repo secret — a standing credential and attack surface for a once-per-package action. Rejected: the maintenance/risk cost outweighs a one-time UI click. |

The default `GITHUB_TOKEN` cannot change package visibility, so the flip is a
manual GitHub UI / API action regardless. Option B accepts that one-time cost and
spends the engineering effort on the part that recurs (verification), not the
part that happens once (the flip).

### Verification mechanism: manifest resolution, not `docker pull`

The consumer-visible failure in #492 is the registry refusing to resolve the
manifest anonymously (403 at the package level). Pulling image layers tests the
same auth decision but downloads ~3 GB (Android) for no extra signal. So
`verify_published_image.sh` does a `HEAD` on
`/v2/<repo>/manifests/<tag>` using the standard OCI/Docker token handshake:

```
  HEAD https://<host>/v2/<repo>/manifests/<tag>
        │
        ├── 200 ──────────────────────────────▶ anonymously resolvable ✓
        │
        └── 401 + WWW-Authenticate: Bearer realm="…",service="…",scope="…"
                  │
                  GET <realm>?service=<service>&scope=<scope>   (no credentials)
                  │
                  └── token ──▶ HEAD …/manifests/<tag>  Authorization: Bearer <token>
                                     │
                                     ├── 200 ─▶ resolvable ✓
                                     └── 403/401 ─▶ NOT anonymously resolvable ✗ (exit 1)
```

This one code path works for all three registries because they all implement
[RFC-style token auth](https://distribution.github.io/distribution/spec/auth/token/):

- **Docker Hub** — host `registry-1.docker.io`; realm `auth.docker.io/token`.
- **GHCR** — host `ghcr.io`; realm `ghcr.io/token`. A private package returns a
  token whose subsequent manifest read is `403 DENIED` (the #492 signature).
- **Quay** — host `quay.io`; realm `quay.io/v2/auth`.

`Accept` advertises the OCI image index, Docker manifest list, and single-arch
manifest media types so multi-arch indexes resolve.

### Job wiring in `release.yml`

```
  release-android ─┐                         (3 registries × flutter-android)
                   ├──▶ verify-published  ← NEW, if: always()
  release-windows ─┘     no registry login
                         checks the pairs whose release job succeeded
```

- `needs: [release-android, release-windows]`, `if: ${{ always() && (success or
  partial) }}`. `always()` means it never *cancels* either release job —
  preserving the `windows-image-release` "parallel, no mutual cancel" guarantee.
  No `needs:` edge is added *between* the two release jobs.
- Coverage tracks reality via each job's `result`: Android pairs are checked when
  `needs.release-android.result == 'success'`; Windows pairs when
  `needs.release-windows.result == 'success'`. So a `workflow_dispatch`
  Windows-only rebuild (Android skipped) verifies Windows tags only.
- The job logs in *no* registry. A green result therefore means an
  unauthenticated `docker pull` of that tag would succeed — the readme reader's
  exact path.

`verify-published` is a tripwire, not a gate: the images are already pushed by
the time it runs. Its value is failing the *run* visibly so the maintainer fixes
visibility, not preventing a (already-completed) publish.

## Automated Test Strategy

- **Unit-ish, local, pre-merge:** run `script/verify_published_image.sh` locally
  against the **current** release (`3.44.1`) before the visibility flip. It MUST
  exit non-zero for `ghcr.io/gmeligio/flutter-android:3.44.1` (reproducing #492)
  and exit zero for `docker.io/gmeligio/flutter-android:3.44.1` and
  `ghcr.io/gmeligio/flutter-windows:3.44.1`. This proves the script distinguishes
  public from private before it ever guards a release.
- **Integration, real, post-merge:** the first `release.yml` run after merge
  executes `verify-published` against live registries. After the GHCR flip, all
  published pairs resolve; Quay's real state is revealed here.
- **Critical path:** the script's exit code → the job's success/failure → the
  release run's status. No mocking; the registries are the system under test.
- No new test framework: the script is plain `curl` + `bash`, consistent with
  the repo's existing `script/*.sh` helpers.

## Observability

- Per check, the job logs one line: `<registry>/<repo>:<tag> → HTTP <code>
  (<resolvable|NOT resolvable>)`, so the log reads as a checklist.
- On failure the script exits non-zero with a message naming the exact
  `<registry>/<repo>:<tag>` that is not anonymously resolvable; the failing
  `verify-published` job is the surface in the release run's check list.
- No silent-failure path: every checked pair must produce a 200 after the
  anonymous handshake or the step exits non-zero (`set -euo pipefail`). An
  unexpected HTTP status (5xx, network error) is treated as failure, not skipped.

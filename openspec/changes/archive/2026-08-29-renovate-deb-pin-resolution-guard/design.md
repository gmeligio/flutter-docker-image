## Context

`android.Dockerfile` pinned `openjdk-17-jdk-headless` to `17.0.20+8-1~deb12u1`, published in no
suite the image enables. `main` could not cold-build for three weeks (#555).

Renovate stayed silent. A cache-cold local run of Renovate 44.46.0 (research.md §4) shows it
*did* fetch the bookworm index and *did* read the ceiling `17.0.19+10-1~deb12u2`, then emitted
`updates: []` because
`isGreaterThan('17.0.20+8-1~deb12u1', '17.0.19+10-1~deb12u2') === true`. Renovate proposes
upgrades only, so a pin above the archive is indistinguishable from one that is current.

A second defect surfaced while verifying the fix. The obvious repin target — the base-suite
`17.0.19+10-1~deb12u2`, which genuinely exists in bookworm — **also does not build**:

```
openjdk-17-jdk-headless : Depends: openjdk-17-jre-headless (= 17.0.19+10-1~deb12u2)
                          but 17.0.20.1+1-1~deb12u1 is to be installed
```

`bookworm-security` published `17.0.20.1+1-1~deb12u1` on 2026-08-18. apt selects it for the
JRE, and the JDK's strict equality dependency forces the JDK to match. The only installable pin
is the security one.

## Goals / Non-Goals

**Goals:**
- Restore cold-buildability of `main`.
- Stop `.github/renovate.json` from mandating suite coverage no configuration can deliver, and
  from omitting the suite the working pin actually comes from.
- Correct the spec's record of what happened.

**Non-Goals:**
- **A dedicated pin-verification CI check.** One was built and removed — see Decision 1.
- Restoring `-updates` / `-security` fetch coverage. Blocked upstream
  ([renovate#44330](https://github.com/renovatebot/renovate/issues/44330)); no config works
  around a hardcoded `const compression = 'gz'`.
- Fixing the hardcoded-`17` / derived-major collision in `android.Dockerfile:162`. Tracked in
  [#536](https://github.com/gmeligio/flutter-docker-image/issues/536).
- Removing the build cache. It protects a Flutter SDK clone, a `gem install`, and an Android
  SDK download; it is not what let #555 through.

## Decisions

### 1. No new CI check — the image build already covers the PR path

A `check_deb_pins.sh` guard was implemented, tested, wired into `build.yml`, and then removed.
The reasoning is worth keeping, because the guard was intuitively appealing and wrong.

The claim it rested on was that CI never re-executes `apt-get install`. That is true only while
the Dockerfile is unchanged. **Editing a pin changes the file, which changes the layer cache
key, which forces `apt-get install` to re-run** — verified directly: with a warm cache from a
good build, changing the `ARG` to a bad version fails the build with
`E: Version '...' was not found`. `build.yml` builds the android stage on every PR, so a pin
edited to an uninstallable value fails its own PR.

That leaves one non-duplicated case: a pin rotting with **no repo change**, when a security
upload moves apt's candidate underneath a committed pin. Only a scheduled run covers it. That
was considered and rejected — finding the break on the next PR is the intended workflow here,
so a recurring job and notification path buys a narrower detection window the project does not
need.

With the scheduled run gone, the guard checked only what the build in the same workflow already
checked, a few minutes earlier. Removed.

_What was actually lost:_ a specific error naming `apt would install instead: <candidate>`,
which is the line that identified the real fix in this investigation. The build failure names
the unmet dependency but not the candidate. Judged a nicety, not a justification.

_Conclusion drawn instead:_ #555 was a review failure, not a tooling gap. PR #529 said "CI on
this PR is the verification" and was merged without that verification passing.

### 2. Keep the `-security` registryUrls; drop only `-updates`

The correct pin for `openjdk-17-jdk-headless` lives in `bookworm-security`
(`17.0.20.1+1-1~deb12u1`). Security coverage is a *correctness* concern for this package, not
merely currency — dropping those URLs would mean Renovate can never propose the version the
image needs.

But the URLs cannot be fetched either: Renovate hardcodes `const compression = 'gz'` and Debian
publishes no `Packages.gz` on `-security` or `-updates`. Both keeping and dropping are wrong in
different ways, and neither is fixable from config.

Resolution: **keep `-security`, drop `-updates`**, and make the gap explicit in the
`description` rather than in silence.

- Keeping `-security` costs 404s that were already happening, and encodes the correct intent —
  when renovate#44330 lands, coverage resumes with no edit.
- Dropping `-updates` removes URLs that are both unfetchable *and* not where any pin resolves
  from.

_Alternative considered:_ drop all four. Rejected once the security version turned out to be
load-bearing — the config would then contradict where the pin comes from, which is the same
class of false-premise-in-config that produced #555.

### 3. Verify the repin by cold-building the apt layer, not by reading apt output

#529 took its value from a failing build's error text and could not confirm it. The replacement
was verified by building the actual apt layer with `--no-cache` against the real bookworm
sources, confirming both that the base-suite version fails and that the security version
installs (`openjdk version "17.0.20.1"`).

## Automated Test Strategy

No new automated tests. The verification that matters already exists: `build.yml` builds the
android stage on every PR, and a changed pin forces `apt-get install` to re-run. The repin was
verified by a `--no-cache` build of the apt layer before committing.

The `renovate.json` change is syntax-checked by `mise run lint`
(`renovate-config-validator`), and authoritatively validated by the Renovate app itself on the
`renovate/reconfigure` branch. Neither checks that a suite is fetchable — that is what the
`description` comments and this design record instead.

## Observability

The `-security` URLs still 404 on every Renovate run, swallowed at debug level. That remains
invisible in the job summary, and no repository change can surface it while the upstream gap
persists. It is recorded in the `description` fields so the next reader of the config finds the
explanation where they will look for it, rather than rediscovering it from a job log.

An uninstallable pin is observable where it matters: as a failed image build on the PR that
introduces it, naming the version and the unmet dependency.

## Risks / Trade-offs

- **A pin can rot with no repo change** — a security upload moves apt's candidate and the
  committed pin stops being installable → Surfaces on the next PR touching the Dockerfile
  rather than when it happens. Accepted deliberately; this is the delay #555 exhibited.
- **Renovate cannot see `-security` uploads** → It will not propose the upgrade, so the pin
  goes stale until someone notices. The kept `registryUrls` entry means this self-corrects when
  upstream lands `.xz` support.
- **Keeping unfetchable `-security` URLs looks like an oversight** → Mitigated by the
  `description` field naming the upstream blocker, so the config reads as intentional.
- **The repin tracks a security upload, so it may go stale the same way again** → True, and
  unavoidable without either the upstream fix or a scheduled check. The strict-equality
  dependency means this package is structurally prone to it.

## Migration Plan

1. **Repin** `android.Dockerfile` to `17.0.20.1+1-1~deb12u1`, verified by a `--no-cache` build
   of the apt layer. Unblocks cold builds. *(Done.)*
2. **Adjust `renovate.json`** on a `renovate/reconfigure` branch (drop `-updates`, keep and
   document `-security`); Renovate validates it there. *(Done.)*
3. **Sync the spec.** *(Done.)*

Rollback: each step is a standalone revert.

## Open Questions

- ~~Should a pin check run on a schedule?~~ Resolved: no. Finding the issue on the next PR is
  the intended workflow.
- ~~Where should a pin guard run?~~ Resolved: nowhere — the image build already covers the PR
  path (Decision 1).
- **Should #536 absorb the strict-equality fragility?** The hardcoded-`17` collision and this
  package's `Depends: (= <version>)` behaviour are related: both make the openjdk pin harder to
  maintain than the other 13. Worth noting there rather than opening a third issue.

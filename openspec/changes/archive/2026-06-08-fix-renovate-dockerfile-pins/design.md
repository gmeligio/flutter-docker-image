## Context

`android.Dockerfile` pins nine Debian apt-package versions via the `# renovate: suite=… depName=…` + `ARG *_VERSION="…"` convention. A `deb`-datasource custom manager in `.github/renovate.json` is responsible for bumping them. Its `managerFilePatterns` is `["/^Dockerfile$/"]`.

Per Renovate's string-pattern-matching rules, a `/…/`-delimited value is an anchored re2 regex matched against the full repo-relative path. `^Dockerfile$` therefore requires a file named exactly `Dockerfile` at the repo root. That file was renamed `Dockerfile → android.Dockerfile` in #317 (`ef6cbea`), and the renovate pattern was never updated — so the manager has matched zero files ever since. Renovate's config validator (`script/renovate_validate.sh`) only checks JSON schema validity; `/^Dockerfile$/` is schema-valid, so the breakage shipped silently.

A second, narrower defect: two pins (`BUILD_ESSENTIAL_VERSION` line 99, `BUNDLER_VERSION` line 122) are declared with `ENV` rather than `ARG`. The `matchStrings` regex is hardcoded to `ARG`, so even after the file pattern is fixed, an `ENV`-declared pin stays invisible.

## Goals / Non-Goals

**Goals:**
- Make the deb custom manager match `android.Dockerfile` so its nine apt pins receive automated upgrades.
- Choose a file pattern that survives a future Dockerfile rename or addition without re-editing `renovate.json`.
- Establish a single, enforceable convention: every self-pinned `*_VERSION` value is an `ARG`.

**Non-Goals:**
- Adding a CI guard that asserts the manager extracts ≥1 dependency (real recurrence defense, but a separate concern — proposed as a follow-up, not folded into this fix to keep it trivially reviewable).
- Widening `matchStrings` to tolerate `ENV` (rejected — see Decisions).
- Normalizing the uppercase/lowercase `ARG` split (intentional distinction — preserved).
- Touching `windows.Dockerfile` (no `# renovate:` apt pins) or the `gx.toml` action manager.

## Decisions

**Decision 1: Use the glob `**/*.Dockerfile`, not an anchored per-file regex.**
A glob matches any `*.Dockerfile` at any depth and is case-insensitive by default. This eliminates the exact drift that #317 introduced: renaming or adding a `*.Dockerfile` requires no `renovate.json` edit.
- *Alternative — anchored regex list* (`/^android\.Dockerfile$/`, `/^windows\.Dockerfile$/`): matches the working `gx.toml` manager's style and is maximally precise, but reintroduces a manual drift surface — every new Dockerfile must be added by hand. Rejected: it's the property that broke last time.
- *Alternative — suffix regex* (`/\.Dockerfile$/`): equivalent coverage to the glob but less familiar to readers. Glob preferred for readability.
- `windows.Dockerfile` will also match, which is harmless: it carries no `# renovate:` apt pins, so `matchStrings` extracts nothing from it.

**Decision 2: Fix the two stray pins to `ARG`; keep `matchStrings` strict (`ARG`-only).**
Both `BUILD_ESSENTIAL_VERSION` and `BUNDLER_VERSION` are consumed at build time on the immediately following line and read by nothing else (verified by grep across `android.Dockerfile` and `script/`). They have no reason to be `ENV`.
- *Alternative — widen the regex to `(?:ARG|ENV)`*: tolerates either keyword, but bakes the inconsistency in (a future reader asks "why is build-essential `ENV`?") and loosens the regex so it could match an unrelated future `ENV …_VERSION`. Rejected in favor of the more semantic fix.
- *Security rationale:* `ENV` persists a build-only value into the final image's runtime environment and `docker inspect` metadata (least-surprise / image-hardening concern), and a runtime `BUNDLER_VERSION` env var can collide with what `bundler` reads. `ARG` confines the value to build time. The version string is not secret, so confidentiality impact is nil — but the rule "build-only data belongs in `ARG`" still applies.

**Decision 3: Preserve the uppercase/lowercase `ARG` split.**
UPPERCASE-with-default = self-pinned, Renovate-managed; lowercase-no-default = injected via `--build-arg` from the CI matrix (e.g. `flutter_version`). Casing is irrelevant to Renovate's regex (it keys off the `# renovate:` comment and the `_VERSION="…"` shape), but it's a useful reader signal. Flattening it would destroy information, not add consistency.

## Risks / Trade-offs

- **[Glob matches `windows.Dockerfile` too]** → Harmless: no `# renovate:` apt pins there, so nothing is extracted. No action needed.
- **[First successful run opens up to nine upgrade PRs at once]** → Bounded by the weekly schedule and the repo's existing `prHourlyLimit`/grouping config (`group:allNonMajor`). Expected and desirable — these pins are overdue.
- **[Schema validator still can't catch a future zero-match regression]** → Acknowledged; out of scope here. Tracked as the follow-up CI-guard concern in Non-Goals. This fix does not make recurrence *more* likely (the glob is rename-proof), it just doesn't add the independent guardrail.
- **[Renovate may propose `currentValue` mismatches if a pinned version is not in the configured suite]** → Pre-existing behavior of the deb datasource, unchanged by this fix; surfaces as a normal Renovate PR, not a silent failure.

## Automated Test Strategy

The contract is verified at two levels:
1. **Static / review-time:** `script/renovate_validate.sh` confirms the config remains schema-valid after the pattern change. A maintainer (or a future CI guard) can additionally run `npx renovate --platform=local` and grep the debug log for `android.Dockerfile` and the extracted deb depNames to confirm the manager now matches nine pins rather than zero — this is the critical-path check that distinguishes "schema-valid" from "actually matches."
2. **Empirical:** the first weekly Renovate run after merge is the end-to-end proof — it either opens PRs for the stale pins or it does not. No new test infrastructure is introduced by this change; the follow-up CI guard (Non-Goal) would formalize the dry-run assertion.

## Observability

The failure this change fixes was *silent* — that is the core lesson. The deb manager matching zero files produces no error, no warning, and no PR; the only symptom is the absence of upgrade PRs, which is invisible without going looking. After this fix:
- A correct manager surfaces as visible upgrade PRs on the weekly schedule (the positive signal).
- A regression would again be silent under today's tooling — which is precisely why the follow-up CI dry-run guard (asserting ≥1 deb dependency extracted, failing the PR otherwise) is called out as the real recurrence defense. Within this change's scope, the `ENV → ARG` normalization removes one silent-staleness vector by making the strict `ARG` regex able to see all nine pins.

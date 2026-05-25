## 1. Capture the ruleset as code

- [ ] 1.1 `gh api repos/gmeligio/flutter-docker-image/rulesets/1959230 | jq '.' > .github/rulesets/main.json`. Strip API-only fields (`id`, `node_id`, `created_at`, `updated_at`, `source`, `source_type`, `_links`, `current_user_can_bypass`); the remaining shape matches what `PUT /repos/{owner}/{repo}/rulesets/{id}` accepts.
- [ ] 1.2 Add `.github/rulesets/README.md` documenting (a) the apply command (`gh api -X PUT /repos/.../rulesets/1959230 --input main.json`), (b) the rule that ruleset edits go through PR review, (c) why GitHub does not yet auto-apply rulesets from a repo file.
- [ ] 1.3 In the JSON, add a top-of-file comment (technically a sibling note in the README — JSON does not allow comments) recording the deliberate choice to leave `required_approving_review_count: 0` for solo-maintainer reasons, with a link to this proposal.

## 2. Audit and (if safe) narrow the bypass actor

- [ ] 2.1 Resolve `actor_id: 987256, actor_type: Integration` to a specific GitHub App. Try `gh api /repos/gmeligio/flutter-docker-image/installations` and match by app slug; cross-reference with the Apps installed at https://github.com/settings/installations.
- [ ] 2.2 Confirm what the App is used for. Most likely candidate is the `verified-commit` App referenced in `changelog.yml:44-48` and `tag.yml:20-26` for App-token-authenticated pushes.
- [ ] 2.3 Test whether `changelog.yml` / `tag.yml` push commits directly (skipping the PR + merge flow) — if they DO push directly, the `bypass_mode: always` is required and SHALL be kept. If they push through PRs (via `peter-evans/create-pull-request` or similar), narrow to `bypass_mode: pull_request`.
- [ ] 2.4 If the App is unidentifiable or unused, remove the `bypass_actors` entry entirely. Apply the change to ruleset `1959230` via `gh api -X PUT`. Update `.github/rulesets/main.json` to match.

## 3. Add the bot auto-approve workflow

- [ ] 3.1 Create `.github/workflows/auto-approve-bots.yml` with `on: pull_request_target: { types: [opened, synchronize, reopened] }`, top-level `permissions: { contents: read, pull-requests: write }`, harden-runner audit step (from p7's `ci-workflow-hardening` spec).
- [ ] 3.2 Hard-code two allowlists in the workflow body: author allowlist (`renovate[bot]`, `verified-commit[bot]`) and path allowlist (`renovate.json`, `package*.json`, `pnpm-lock.yaml`, `mise.toml`, `.github/gx.toml`, `changelog.md`, `config/version.json`). Changes to either list go through PR review like any other code change.
- [ ] 3.3 Steps: harden-runner; `actions/create-github-app-token` (using `VERIFIED_COMMIT_ID` / `VERIFIED_COMMIT_KEY`); `actions/github-script` that (a) checks the author against the author allowlist, (b) calls `pulls.listFiles` and checks every returned path against the path allowlist, (c) on pass: `pulls.createReview({event: 'APPROVE', body: 'Auto-approved per .github/workflows/auto-approve-bots.yml — author and changed paths are in the trusted allowlists. Threat model: openspec/.../p10-strengthen-branch-protection/proposal.md'})`, (d) logs the decision to the run summary.
- [ ] 3.4 Add a header comment at the top of the workflow file pointing to the threat-model section in `openspec/changes/p10-strengthen-branch-protection/proposal.md`. Explicitly state "no actions/checkout — this is a security invariant; do not add one in a follow-up".

## 4. Document the governance model

- [ ] 4.1 Create `.github/SECURITY.md` with sections: "Sole-maintainer governance", "Active ruleset" (link to `.github/rulesets/main.json` and the GitHub UI URL), "Why CodeReview Scorecard score is low" (accepted ceiling, recovery path = co-maintainer), "Trusted bots" (link to `auto-approve-bots.yml`), "Reporting vulnerabilities" (GitHub's private vulnerability reporting flow).
- [ ] 4.2 If `.github/CODEOWNERS` does not already note the review model, prepend a header comment.

## 5. Verify

- [ ] 5.1 Trigger a Renovate run (or open a fake PR from the `verified-commit` App). Confirm `auto-approve-bots.yml` runs, posts an APPROVE within ~30 s, and the PR can auto-merge if Renovate has automerge enabled.
- [ ] 5.2 Open a PR from `renovate[bot]` that touches a file OUTSIDE the path allowlist (simulate by editing a non-allowlisted file in a Renovate-style branch). Confirm the workflow runs, logs `decision=SKIP reason=path X not in allowlist`, and does NOT post an approval.
- [ ] 5.3 Confirm the bypass-actor change (if any) did not break `changelog.yml` / `tag.yml` by waiting for the next version bump or by dispatching them manually.
- [ ] 5.4 Wait one Scorecard scan cycle. Record the new `BranchProtectionID` and `CodeReviewID` scores in the archived proposal. Confirm `BranchProtectionID` improves if the bypass-actor narrowing landed; accept that `CodeReviewID` may not improve materially.

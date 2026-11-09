# Tasks

## 1. Remove the drifted spec

- [ ] 1.1 Delete `openspec/specs/ci-parallel-image-validation/` (design D1); verify `git grep -n ci-parallel-image-validation -- ':!openspec/changes'` lists only `.github/workflows/build.yml:189`
- [ ] 1.2 Reword the `.github/workflows/build.yml:189` comment to cite `ci-image-vulnerability-scan`; verify the `git grep` from 1.1 returns nothing and `git diff .github/workflows/build.yml` touches only that comment

## 2. Purposes (#561)

- [ ] 2.1 Rewrite `openspec/specs/ci-image-handoff/spec.md` Purpose to the D5 text; verify `grep -n test_image openspec/specs/ci-image-handoff/spec.md` returns nothing
- [ ] 2.2 Add title, `## Purpose` (D5 text) and `## Requirements` to `ci-image-anonymous-availability` and `generated-docs-and-examples`; add `## Purpose` to `repository-wiki` and `windows-version-tracking`; verify `openspec validate <id> --type spec` passes for each of the four

## 3. Spec rules (#599)

- [ ] 3.1 Reword `openspec/config.yaml` `context:` and `rules.specs` per D7; verify `grep -c "desktop user" openspec/config.yaml` prints `0` and `openspec instructions specs --change refresh-ci-parallel-image-validation --json` lists the new migration rule

## 4. Spec validation in CI (#598)

- [ ] 4.1 Add `[tasks.specs]` to `mise.toml` running `openspec validate --all`; verify `mise run specs` exits 0
- [ ] 4.2 Add `.github/workflows/openspec.yml` per D6 and run `gx tidy`; verify `gx lint` passes and `.github/gx.lock` covers its actions
- [ ] 4.3 Push the PR branch; verify the `Validate specs` check runs and passes, then push a commit dropping one spec's `## Purpose`, verify the check fails naming that spec, and revert it

## 5. Integration check

- [ ] 5.1 Verify `openspec validate refresh-ci-parallel-image-validation --strict` passes
- [ ] 5.2 On a scratch copy of `openspec/`, run `openspec archive refresh-ci-parallel-image-validation --yes`; verify it succeeds and `openspec validate --all` reports 0 failures, including `change/ubuntu-26-runners` if still active

## Workflow follow-up

- Run `/opsx:archive` on the PR branch, push, then merge.

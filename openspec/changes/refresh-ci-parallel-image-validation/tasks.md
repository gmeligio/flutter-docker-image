# Tasks

## 1. Remove the drifted spec

- [ ] 1.1 Delete `openspec/specs/ci-parallel-image-validation/` (design D1); verify `git grep -n ci-parallel-image-validation -- ':!openspec/changes'` lists only `.github/workflows/build.yml:189`
- [ ] 1.2 Reword the `.github/workflows/build.yml:189` comment to cite `ci-image-vulnerability-scan`; verify the `git grep` from 1.1 returns nothing and `git diff .github` touches only that comment

## 2. Refresh surviving specs

- [ ] 2.1 Rewrite `openspec/specs/ci-image-handoff/spec.md` Purpose to name `build-image` and per-image handoff (design D4); verify `grep -n test_image openspec/specs/ci-image-handoff/spec.md` returns nothing
- [ ] 2.2 Verify `openspec validate refresh-ci-parallel-image-validation --strict` passes

## 3. Integration check

- [ ] 3.1 On a scratch copy of `openspec/`, run `openspec archive refresh-ci-parallel-image-validation --yes`; verify it succeeds and `openspec validate --specs` reports 4 failures (the #561 set minus `ci-parallel-image-validation`)

## Workflow follow-up

- Run `/opsx:archive` on the PR branch, push, then merge.

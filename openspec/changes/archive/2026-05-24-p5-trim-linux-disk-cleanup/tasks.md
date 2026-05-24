## 1. Trim the Linux cleanup script

- [x] 1.1 In `.github/actions/clean-runner-disk/action.yml`, in the `[Linux] Clean runner disk` step, remove every `apt-get remove ...` line for browsers, .NET, aspnetcore, Swift/LLVM, Azure CLI, mono, Google Cloud SDK / CLI, PowerShell.
- [x] 1.2 Keep `apt-get autoremove -y` and `apt-get clean` as a single trailing pair.
- [x] 1.3 Add `rm -rf` lines covering the package install dirs that the removed `apt-get` calls used to handle (paths listed in proposal "What Changes").
- [x] 1.4 Run the step manually inside a `workflow_dispatch` PR and time it. Confirm ≤ 2 minutes wall-clock — satisfies the modified spec requirement. _PR #464 build_image (job 77594156664): composite step 11:38:51→11:40:47 = **1m56s (116 s)**. Under budget._

## 2. Update the capability spec

- [x] 2.1 Verify `p4-unify-runner-disk-cleanup` is archived (its specs are now under `openspec/specs/ci-runner-disk-cleanup/spec.md`). _Confirmed: p4 archived at commit 7672004; `openspec/specs/ci-runner-disk-cleanup/spec.md` exists._
- [x] 2.2 The MODIFIED Requirements in this change's spec delta replace the existing "Linux cleanup retains its current ~3-minute budget" requirement with a 2-minute budget and a freed-bytes-not-tactics contract.

## 3. Verify on a real PR before merge

- [x] 3.1 Push as a draft PR. Confirm the post-clean assertion (`≥ 20 GB free on /`) still passes — this is the regression alarm. _PR #464 build_image: `clean-runner-disk: 127.00 GB free on / (threshold 20 GB) — OK`._
- [ ] 3.2 Confirm the new wall-clock is ≤ 2 minutes at the median across 3 consecutive runs. _Run 1/3 done at 1m56s; needs two more re-pushes or defer to post-merge p95 check (4.1)._
- [x] 3.3 Compare the freed-bytes number from the job-summary line against the pre-change baseline (~30-40 GB). Confirm it has not regressed by more than 2 GB. _PR #464: before 89.4 GB free → after 127 GB free = **~38 GB freed**, within the 30-40 GB baseline. No regression._

## 4. Post-merge closure check

- [ ] 4.1 After 10 post-merge runs of `build.yml` and `ci.yml`, query the median Linux `Clean runner disk` step duration and confirm ≤ 2 minutes at the 95th percentile.
- [ ] 4.2 Watch the next runner-image update (cycles every 1-2 weeks per GitHub). If the post-clean assertion fails the morning after a new image, an undisclosed new tool was added — add an `rm -rf` line for it and document the recurrence.

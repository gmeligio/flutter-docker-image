---
model: inherit
name: openspec-archive-change
description: Archive a completed change in the experimental workflow. Use when the user wants to finalize and archive a change after implementation is complete.
license: MIT
compatibility: Requires openspec CLI.
metadata:
  author: openspec
  version: "1.0"
  generatedBy: "1.3.1"
---

Archive a completed change in the experimental workflow.

**Input**: Optionally specify a change name. If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Steps**

1. **If no change name provided, prompt for selection**

   Run `openspec list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select.

   Show only active changes (not already archived).
   Include the schema used for each change if available.

   **IMPORTANT**: Do NOT guess or auto-select a change. Always let the user choose.

2. **Check artifact completion status**

   Run `openspec status --change "<name>" --json` to check artifact completion.

   Parse the JSON to understand:
   - `schemaName`: The workflow being used
   - `artifacts`: List of artifacts with their status (`done` or other)

   **If any artifacts are not `done`:**
   - Display warning listing incomplete artifacts
   - Use **AskUserQuestion tool** to confirm user wants to proceed
   - Proceed if user confirms

3. **Check task completion status**

   Read the tasks file (typically `tasks.md`) to check for incomplete tasks.

   Count tasks marked with `- [ ]` (incomplete) vs `- [x]` (complete).

   **If incomplete tasks found:**
   - Display warning showing count of incomplete tasks
   - Use **AskUserQuestion tool** to confirm user wants to proceed
   - Proceed if user confirms

   **If no tasks file exists:** Proceed without task-related warning.

4. **Assess delta spec sync state**

   Check for delta specs at `openspec/changes/<name>/specs/`. If none exist, proceed without sync prompt.

   **If delta specs exist:**
   - Compare each delta spec with its corresponding main spec at `openspec/specs/<capability>/spec.md`
   - Determine what changes would be applied (adds, modifications, removals, renames)
   - Show a combined summary before prompting

   **Always sync specs automatically** — do NOT prompt the user. If there are changes to sync, proceed directly.

   Use Task tool (subagent_type: "general-purpose", prompt: "Use Skill tool to invoke openspec-sync-specs for change '<name>'. Delta spec analysis: <include the analyzed delta spec summary>"). Proceed to archive after sync completes.

<!-- opsx-verify-scoring-patch -->

5. **Verify implementation**

   Check for `.verify-passed` marker at `openspec/changes/<n>/.verify-passed`.

   **If marker does NOT exist:**
   - Invoke Skill tool: `openspec-verify-change` for change `<n>`
   - Wait for the verdict:
     - **FAIL** → block archive, show score table, list CRITICAL issues
     - **CONDITIONAL** → show score table + warnings, ask user to confirm
     - **PASS** → write marker: `echo "passed" > "openspec/changes/<n>/.verify-passed"`, continue
   - Max 3 retry cycles: fix → re-verify → check verdict

   **If marker EXISTS:** show "✓ Verified" and continue.

6. **Perform the archive**

   Create the archive directory if it doesn't exist:
   ```bash
   mkdir -p openspec/changes/archive
   ```

   Generate target name using current date: `YYYY-MM-DD-<change-name>`

   **Check if target already exists:**
   - If yes: Fail with error, suggest renaming existing archive or using different date
   - If no: Move the change directory to archive

   ```bash
   mv openspec/changes/<name> openspec/changes/archive/YYYY-MM-DD-<name>
   ```


<!-- opsx-git-commit-patch -->

7. **Git: commit the archive move, then push and open a PR**

   By this point, step 6 has moved `openspec/changes/<name>/` into
   `openspec/changes/archive/<DATE>-<name>/`. The archived proposal lives at
   `openspec/changes/archive/<DATE>-<name>/proposal.md` and is used to
   compose the PR body below.

   **7a. Branch guard — refuse to PR from trunk.**

   ```bash
   BRANCH=$(git rev-parse --abbrev-ref HEAD)
   case "$BRANCH" in
     main|master|trunk)
       echo "Refusing to push and PR from trunk branch '$BRANCH'."
       echo "Create a feature branch first (e.g. 'git switch -c archive/<name>'), then re-run /opsx:archive."
       exit 1
       ;;
   esac
   ```

   **7b. Commit the archive move.** Stage `openspec/` and commit only if
   there is a staged diff. Build a Conventional Commit prefix from the
   staged change — do not hardcode the type, and do not use the change-id
   as the scope:

   - **type**: infer from the diff's user-facing *outcome*, not the
     technique used (a refactor that fixes a bug is `fix`, not `refactor`).
     Choose one of: `feat`, `fix`, `docs`, `chore`, `ci`, `refactor`,
     `perf`, `test`, `build`, `style`, `revert`. A move that only relocates
     artifacts under `openspec/changes/` is `docs`.
   - **scope**: the affected code area, derived from the primary top-level
     directory or module the diff touches — the existing directory/module
     name, not an invented synonym, and not the change-id. An archive move
     touching only `openspec/changes/` yields scope `openspec`. When the
     diff spans multiple unrelated areas, pick the dominant area.
   - **subject**: `archive <change-name>`.

   Print the chosen `type(scope): subject` before committing, then:

   ```bash
   git add -A openspec/
   git diff --cached --quiet || git commit -m "<type>(<scope>): archive <change-name>"
   ```

   **7c. `OPSX_NO_PR=1` opt-out.** When this environment variable is set,
   commit only — skip push, PR creation, and CI watch — and announce
   the skip with a single banner. Then jump to step 9 (display summary).

   ```bash
   if [ "${OPSX_NO_PR:-0}" = "1" ]; then
     echo "OPSX_NO_PR=1 set — skipping push and PR creation."
     # continue to step 9 (Display summary)
   fi
   ```

   **7d. `gh` not installed — fail fast.** If `OPSX_NO_PR` is unset and
   `gh` is missing, exit non-zero with an actionable hint.

   ```bash
   if ! command -v gh >/dev/null 2>&1; then
     echo "gh CLI not found. Install gh, or re-run with 'OPSX_NO_PR=1 /opsx:archive' to skip PR creation."
     exit 1
   fi
   ```

   **7e. Idempotent push.** If the branch already tracks an upstream and
   is in sync (no `ahead` count), skip the push. Otherwise push with `-u`.

   ```bash
   if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1 \
      && [ -z "$(git rev-list "@{u}"..HEAD)" ]; then
     echo "Branch already up-to-date with upstream — skipping push."
   else
     git push -u origin HEAD
   fi
   ```

   **7f. Compose the PR body from the archived `proposal.md`.** Slice the
   `## Why` and `## What Changes` sections out of
   `openspec/changes/archive/<DATE>-<name>/proposal.md` and append a
   generated-by footer. If either section is missing, fall back to a
   one-line "see commit history" body.

   ```bash
   PROPOSAL="openspec/changes/archive/<DATE>-<name>/proposal.md"
   BODY=$(awk '
     /^## Why$/                 { capture=1; print; next }
     /^## What Changes$/        { capture=1; print; next }
     /^## (Capabilities|Impact)$/ { capture=0 }
     /^## /                     { if (capture && !/^## (Why|What Changes)$/) capture=0 }
     capture                    { print }
   ' "$PROPOSAL")
   if [ -z "$BODY" ]; then
     BODY="See commit history on this branch."
   fi
   BODY="$BODY

   ---
   🤖 Generated by /opsx:archive"
   ```

   **7g. Idempotent PR creation.** Check whether a PR already exists for
   the current branch. Reuse OPEN; refuse CLOSED/MERGED; otherwise create.

   ```bash
   PR_STATE=$(gh pr view --json state,number,url 2>/dev/null \
     | jq -r '.state + " " + (.number|tostring) + " " + .url' \
     || true)

   case "$PR_STATE" in
     OPEN*)
       PR_NUMBER=$(printf '%s\n' "$PR_STATE" | awk '{print $2}')
       PR_URL=$(printf '%s\n' "$PR_STATE" | awk '{print $3}')
       echo "Reusing existing OPEN PR #$PR_NUMBER ($PR_URL)."
       ;;
     CLOSED*|MERGED*)
       STATE=$(printf '%s\n' "$PR_STATE" | awk '{print $1}')
       echo "An existing PR for this branch is $STATE."
       echo "Either reopen it, create a new branch, or re-run with OPSX_NO_PR=1."
       exit 1
       ;;
     *)
       gh pr create --title "<type>(<scope>): <change-name>" --body "$BODY"
       PR_NUMBER=$(gh pr view --json number -q .number)
       PR_URL=$(gh pr view --json url -q .url)
       echo "Opened PR #$PR_NUMBER ($PR_URL)."
       ;;
   esac
   ```

   Conventional-Commit titles are enforced by `bash-guard.sh`. Build the
   `<type>(<scope>)` prefix the same way as the commit in step 7b: infer
   **type** from the diff's user-facing outcome (one of `feat`, `fix`,
   `docs`, `chore`, `ci`, `refactor`, `perf`, `test`, `build`, `style`,
   `revert`), and derive **scope** from the primary code area the change
   touches — the existing directory/module name, not the change-id. Use
   the same `type(scope)` you printed in step 7b.

8. **Watch pipeline and fix issues**

   Skip this step entirely when `OPSX_NO_PR=1`.

   After creating (or reusing) the PR, monitor CI checks:

   ```bash
   gh pr checks "$PR_NUMBER" --watch
   ```

   **If any check fails:**
   - Read the failure logs: `gh run view <run-id> --log-failed`
   - Identify the root cause and fix the issue
   - Commit the fix: `git add -A && git commit -m "fix(<change-name>): <brief description>"`
   - Push: `git push`
   - Re-check: `gh pr checks "$PR_NUMBER" --watch`
   - Repeat until all checks pass (max 3 attempts, then report to user with failure details)

   **If all checks pass:** notify the user and continue to summary.

9. **Display summary**

   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Whether specs were synced (if applicable)
   - Note about any warnings (incomplete artifacts/tasks)

**Output On Success**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** ✓ Synced to main specs (or "No delta specs" or "Sync skipped")

All artifacts complete. All tasks complete.
```

**Guardrails**
- Always prompt for change selection if not provided
- Use artifact graph (openspec status --json) for completion checking
- Don't block archive on warnings - just inform and confirm
- Preserve .openspec.yaml when moving to archive (it moves with the directory)
- Show clear summary of what happened
- If sync is requested, use openspec-sync-specs approach (agent-driven)
- If delta specs exist, always run the sync assessment and show the combined summary before prompting

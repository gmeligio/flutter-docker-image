---
model: sonnet
name: "OPSX: Archive"
description: Archive a completed change in the experimental workflow
category: Workflow
tags: [workflow, archive, experimental]
---

Archive a completed change in the experimental workflow.

**Input**: Optionally specify a change name after `/opsx:archive` (e.g., `/opsx:archive add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

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
   - Prompt user for confirmation to continue
   - Proceed if user confirms

3. **Check task completion status**

   Read the tasks file (typically `tasks.md`) to check for incomplete tasks.

   Count tasks marked with `- [ ]` (incomplete) vs `- [x]` (complete).

   **If incomplete tasks found:**
   - Display warning showing count of incomplete tasks
   - Prompt user for confirmation to continue
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

7. **Git: Commit, push, and create PR**

   Stage and commit the archived change:

   ```bash
   git add -A openspec/
   git diff --cached --quiet || git commit -m "docs: archive <change-name>"
   ```

   Push the branch and create a pull request:

   ```bash
   git push -u origin HEAD
   gh pr create --title "<change-name>" --body "<summary from the proposal>"
   ```

8. **Watch pipeline and fix issues**

   After creating the PR, monitor CI checks:

   ```bash
   gh pr checks <PR-number> --watch
   ```

   **If any check fails:**
   - Read the failure logs: `gh run view <run-id> --log-failed`
   - Identify the root cause and fix the issue
   - Commit the fix: `git add -A && git commit -m "fix(<change-name>): <brief description>"`
   - Push: `git push`
   - Re-check: `gh pr checks <PR-number> --watch`
   - Repeat until all checks pass (max 3 attempts, then report to user with failure details)

   **If all checks pass:** notify the user and continue to summary.

9. **Display summary**
   ```


   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Spec sync status (synced / sync skipped / no delta specs)
   - Note about any warnings (incomplete artifacts/tasks)

**Output On Success**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** ✓ Synced to main specs

All artifacts complete. All tasks complete.
```

**Output On Success (No Delta Specs)**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** No delta specs

All artifacts complete. All tasks complete.
```

**Output On Success With Warnings**

```
## Archive Complete (with warnings)

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** Sync skipped (user chose to skip)

**Warnings:**
- Archived with 2 incomplete artifacts
- Archived with 3 incomplete tasks
- Delta spec sync was skipped (user chose to skip)

Review the archive if this was not intentional.
```

**Output On Error (Archive Exists)**

```
## Archive Failed

**Change:** <change-name>
**Target:** openspec/changes/archive/YYYY-MM-DD-<name>/

Target archive directory already exists.

**Options:**
1. Rename the existing archive
2. Delete the existing archive if it's a duplicate
3. Wait until a different date to archive
```

**Guardrails**
- Always prompt for change selection if not provided
- Use artifact graph (openspec status --json) for completion checking
- Don't block archive on warnings - just inform and confirm
- Preserve .openspec.yaml when moving to archive (it moves with the directory)
- Show clear summary of what happened
- If sync is requested, use the Skill tool to invoke `openspec-sync-specs` (agent-driven)
- If delta specs exist, always run the sync assessment and show the combined summary before prompting

<!-- patch:model-sonnet -->

<!-- patch:verify-scoring -->

<!-- patch:always-sync-specs -->

<!-- patch:git-commit-archive -->

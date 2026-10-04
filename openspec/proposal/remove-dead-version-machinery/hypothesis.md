Framing: Analyze issue #534 and identify the smallest safe cleanup of unused version-update machinery. New replacement scripts, synchronization logic, or standing checks must be justified by a live dependency that simple deletion cannot preserve.

## H1: The issue's nine scripts can all be deleted without replacing a live entry point

- **Claim**: Nine current `script/` files have no executable, documented, or specification-required callers, including indirect and dynamic invocation.
- **Why it matters**: Determines the deletion list and whether the issue's historical count is still actionable.
- **How to verify**: Inspect all scripts and repository references, including workflows, Dockerfiles, Compose, mise, docs, and active specs. A current caller or a smaller current inventory kills the claim.
- **If true → implication**: Delete the nine scripts without introducing replacements.
- **Status**: KILLED (F2)

## H2: The cmdlineTools manifest field has no live consumers

- **Claim**: Removing `android.cmdlineTools` and its schema requirement leaves live generators and tests unchanged.
- **Why it matters**: Determines whether the mirror is a standalone deletion or a coordinated test-generation change.
- **How to verify**: Trace the field through scripts, CUE, committed tests, workflows, and docs. Any live reader kills the claim.
- **If true → implication**: Remove only the manifest field and schema requirement.
- **Status**: KILLED (F3)

## H3: Both 30.0.3 workflow defaults are overwritten before their first consumer

- **Claim**: The two job-level `ANDROID_BUILD_TOOLS_VERSION: 30.0.3` entries never determine a build's installed version.
- **Why it matters**: Determines whether their deletion changes behavior or needs a fallback.
- **How to verify**: Trace step ordering and the environment exporter in CI and release, then invoke the exporter with and without the stale initial value. Any pre-export consumer or different exported argument kills the claim.
- **If true → implication**: Delete the two defaults, retaining the manifest-derived export.
- **Status**: SURVIVED (F5)

## H4: The mirror can be removed while preserving metadata coverage and pinned-version tests

- **Claim**: Version-independent command-line-tools metadata assertions can pass through CUE without cmdline-tools tags while all command tests and other file-content tests remain unchanged.
- **Why it matters**: Determines whether removing the mirror needs replacement version synchronization or can stay a small coordinated cleanup.
- **How to verify**: Export a scratch test fixture through the existing CUE command-test transformation with only NDK, build-tools, and Java tags. Compare command tests, analytics coverage, and repeat-export stability. An incomplete CUE export, unintended changed assertion, or unstable result kills the claim.
- **If true → implication**: Keep a metadata-presence test, remove only the exact-revision assertion and cmdline-tools-specific generation plumbing.
- **Status**: SURVIVED (F7, F9)

## Option disposition

Final decision: preserve the exact-revision test as requested by the maintainer.
H4 records feasibility of the earlier alternative, not approval to remove the drift gate.

| Option | Verdict | Backing hypotheses / facts | Reason |
|---|---|---|---|
| Delete the seven currently unreferenced scripts | ADOPT | H1 killed; F2 | Current evidence supports seven, not the issue's historical count of nine. No replacement implementation is needed. |
| Find two more scripts to make the deletion count nine | REJECT | H1 killed; F2 | The other 12 scripts have live consumers. |
| Delete the two stale workflow defaults | ADOPT | H3 | Exports are identical with and without them. |
| Delete only the cmdlineTools manifest and schema field | REJECT | H2 killed | Leaves a live generator reading a missing field. |
| Remove the mirror and keep version-independent metadata coverage | REJECT | H4; F4 | Feasible, but removes the exact-revision drift gate the maintainer requires. |
| Delete the command-line-tools test entirely | REJECT | H4; F7 | Loses file/identity coverage that the existing framework can retain cheaply. |
| Keep the existing exact revision as a static test literal | ADOPT | H2; F3, F4 | Removes the manifest mirror and generation plumbing while preserving the reviewed upstream-drift gate. Installation remains dynamic. |
| Add real archive pinning and an updater | DEFER | H4; F4 | Changes version-selection policy and build behavior; not required for this cleanup. |
| Remove the 30.0.3 value from .env.example too | DEFER | H3; F8 | It is a live Compose input, not an overwritten workflow default. Local configuration repair is separate work. |
| Add permanent unused-script policing | REJECT | H1; F2 | Adds standing infrastructure to a bounded deletion with no demonstrated recurrence requirement. |

Research closed after two rounds with nine findings. No hypotheses were deleted unverified.
The historical reason for the nine-script count, external/manual consumers, and actual image execution remain unverified; none is asserted as fact.

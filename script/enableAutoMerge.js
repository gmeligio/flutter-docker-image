// Enabling auto-merge is not merging on green: the main ruleset requires
// code-owner review, so this makes the maintainer's approval the merge.
module.exports = async ({ core, context, github }) => {
  const { PR_NUMBER } = process.env

  if (!PR_NUMBER) {
    core.setFailed('Environment variable PR_NUMBER is required.')
    return
  }

  const pull_number = Number(PR_NUMBER)
  const { data: pr } = await github.rest.pulls.get({ ...context.repo, pull_number })

  // A branch behind main cannot merge under strict required checks, and
  // auto-merge never updates it — it waits silently. Update before review:
  // dismiss_stale_reviews_on_push would dismiss an approval an update followed.
  // pr.base.sha is the commit the PR was opened against and does not advance
  // as main does, so ask GitHub how far behind the head actually is.
  const { data: comparison } = await github.rest.repos.compareCommitsWithBasehead({
    ...context.repo,
    basehead: `${pr.base.ref}...${pr.head.sha}`,
  })
  if (comparison.behind_by > 0) {
    try {
      await github.rest.pulls.updateBranch({ ...context.repo, pull_number })
      core.info(`Updated #${pull_number}: it was ${comparison.behind_by} commit(s) behind ${pr.base.ref}.`)
    } catch (error) {
      core.warning(`Could not update #${pull_number} from ${pr.base.ref}: ${error.message}`)
    }
  }

  // updateBranch is asynchronous; auto-merge waits for whatever state the
  // branch settles into, so this does not depend on the update having landed.
  // Both calls are best-effort: a PR without auto-merge is a working outcome
  // (the maintainer merges by hand, as before), a failed run is not.
  try {
    await github.graphql(
      `mutation($id: ID!) {
         enablePullRequestAutoMerge(input: { pullRequestId: $id, mergeMethod: SQUASH }) {
           clientMutationId
         }
       }`,
      { id: pr.node_id },
    )
    core.info(`Auto-merge enabled on #${pull_number}; it will merge once the code owner approves.`)
  } catch (error) {
    core.warning(`Could not enable auto-merge on #${pull_number}: ${error.message}`)
  }
}

const AUTO_MERGE_MUTATION = `mutation($id: ID!) {
  enablePullRequestAutoMerge(input: { pullRequestId: $id, mergeMethod: SQUASH }) {
    clientMutationId
  }
}`

// A best-effort call: the pull request is already correct without it, so a
// failure warns and the maintainer merges by hand, as before.
const attempt = async (core, description, action) => {
  try {
    await action()
    return true
  } catch (error) {
    core.warning(`Could not ${description}: ${error.message}`)
    return false
  }
}

// pr.base.sha is the commit the pull request was opened against and does not
// advance as the base branch does, so ask GitHub for the live distance.
const commitsBehindBase = async (github, repo, pr) => {
  const { data: comparison } = await github.rest.repos.compareCommitsWithBasehead({
    ...repo,
    basehead: `${pr.base.ref}...${pr.head.sha}`,
  })
  return comparison.behind_by
}

// A branch behind the base cannot merge under strict required status checks,
// and GitHub's auto-merge never updates it — it waits, silently. This must run
// before review: dismiss_stale_reviews_on_push discards an approval that a
// branch update follows.
const updateStaleBranch = async ({ core, github, repo, pr, pull_number }) => {
  const behindBy = await commitsBehindBase(github, repo, pr)
  if (behindBy === 0) return

  const updated = await attempt(core, `update #${pull_number} from ${pr.base.ref}`, () =>
    github.rest.pulls.updateBranch({ ...repo, pull_number }),
  )
  if (updated) {
    core.info(`Updated #${pull_number}: it was ${behindBy} commit(s) behind ${pr.base.ref}.`)
  }
}

// SQUASH is the only method the ruleset allows. Enabling auto-merge does not
// merge on green: require_code_owner_review makes the maintainer's approval
// the last unmet requirement, so approving is what merges.
const enableAutoMerge = async ({ core, github, pr, pull_number }) => {
  const enabled = await attempt(core, `enable auto-merge on #${pull_number}`, () =>
    github.graphql(AUTO_MERGE_MUTATION, { id: pr.node_id }),
  )
  if (enabled) {
    core.info(`Auto-merge enabled on #${pull_number}; it will merge once the code owner approves.`)
  }
}

module.exports = async ({ core, context, github }) => {
  const { PR_NUMBER } = process.env

  if (!PR_NUMBER) {
    core.setFailed('Environment variable PR_NUMBER is required.')
    return
  }

  const repo = context.repo
  const pull_number = Number(PR_NUMBER)
  const { data: pr } = await github.rest.pulls.get({ ...repo, pull_number })

  await updateStaleBranch({ core, github, repo, pr, pull_number })

  // updateBranch is asynchronous, and auto-merge waits for whatever state the
  // branch settles into, so enabling does not depend on the update landing.
  await enableAutoMerge({ core, github, pr, pull_number })
}

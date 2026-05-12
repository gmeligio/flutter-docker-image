module.exports = async ({ core, context, github }) => {
  const { NEW_FLUTTER_VERSION } = process.env

  if (!NEW_FLUTTER_VERSION) {
    core.setFailed('Environment variable NEW_FLUTTER_VERSION is required.')
    return
  }

  // If a tag for this version already exists, do nothing.
  try {
    await github.rest.git.getRef({
      owner: context.repo.owner,
      repo: context.repo.repo,
      ref: `tags/${NEW_FLUTTER_VERSION}`,
    })
    return
  } catch (error) {
    if (error.status !== 404) throw error
  }

  // Create a git tag using the GitHub API instead of the git client to skip SSH/GPG key setup.
  await github.rest.git.createRef({
    owner: context.repo.owner,
    repo: context.repo.repo,
    ref: `refs/tags/${NEW_FLUTTER_VERSION}`,
    sha: context.sha,
  })
}

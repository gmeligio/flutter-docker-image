module.exports = async ({ context, octokit }) => {
  const { OLD_FLUTTER_VERSION, NEW_FLUTTER_VERSION } = process.env

  if (OLD_FLUTTER_VERSION === NEW_FLUTTER_VERSION) {
    return
  }

  // Create a git tag using the GitHub API instead of the git client to skip SSH/GPG key setup.
  octokit.rest.git.createRef({
    owner: context.repo.owner,
    repo: context.repo.repo,
    ref: `refs/tags/${NEW_FLUTTER_VERSION}`,
    sha: context.sha,
  })
}

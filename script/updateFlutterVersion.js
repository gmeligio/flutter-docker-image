module.exports = async ({ github, core, fetch }) => {
  async function tarballExists(version, channel) {
    const fileUrl = `https://storage.googleapis.com/flutter_infra_release/releases/${channel}/linux/flutter_linux_${version}-${channel}.tar.xz`

    try {
      const response = await fetch(fileUrl, { method: 'HEAD' })

      return response.ok
    } catch (error) {
      console.error(
        `An error occurred while requesting the file URL: ${fileUrl}`,
        error
      )

      return false
    }
  }

  const query = `query GetLatestTags {
          repository(owner: "flutter", name: "flutter") {
            tags: refs(
              refPrefix: "refs/tags/"
              first: 60
              orderBy: { field: TAG_COMMIT_DATE, direction: DESC }
            ) {
              edges {
                node {
                  version: name
                  target {
                    oid
                  }
                }
              }
            }
          }
        }`

  const rawResult = await github.graphql(query)
  const stableTagPattern = /^\d+\.\d+\.\d+$/g
  const tags = rawResult.repository.tags.edges
  const latestTag = tags.find((tag) => tag.node.version.match(stableTagPattern))

  const fs = require('fs')
  const resultPath = 'config/version.json'
  const data = fs.readFileSync(resultPath, 'utf8')
  const json = JSON.parse(data)

  const version = latestTag.node.version

  // TODO: Split Android versions trigger on flutter version change

  // Sometimes Flutter publishes stable versions to the beta channel because of it's release process.
  // https://github.com/flutter/flutter/wiki/Flutter-build-release-channels

  let channel
  if (await tarballExists(version, 'stable')) {
    channel = 'stable'
  } else if (await tarballExists(version, 'beta')) {
    channel = 'beta'
  } else {
    core.setFailed(
      `Flutter version ${version} doesn't exist in stable or beta channels.`
    )

    return false
  }

  // Export FLUTTER_VERSION for the next steps
  core.exportVariable('FLUTTER_VERSION', version)
  core.exportVariable('FLUTTER_CHANNEL', channel)

  // Update result file, i.e. version.json
  const result = {
    ...json,
    flutter: {
      channel,
      commit: latestTag.node.target.oid,
      version,
    },
  }

  fs.writeFileSync(resultPath, JSON.stringify(result, null, 4))
}

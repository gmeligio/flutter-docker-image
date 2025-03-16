module.exports = async ({ core, fetch }) => {
  const linuxReleasesUrl =
    'https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json'
  const stableReleasePattern = /^\d+\.\d+\.\d+$/g
  const resultPath = 'config/flutter_version.json'

  /**
   * Downloads the flutter releases from URL
   *
   * @param {*} fileUrl
   * @returns object|boolean
   */
  async function downloadReleases(core, fileUrl) {
    try {
      const response = await fetch(fileUrl)

      return response.json()
    } catch (error) {
      core.error(
        `An error occurred while requesting the file URL ${fileUrl}: ${error}`
      )

      return false
    }
  }

  const linuxReleasesResponse = await downloadReleases(core, linuxReleasesUrl)

  if (linuxReleasesResponse === false) {
    core.setFailed(
      `Could not download Flutter version manifest from ${fileUrl}.`
    )

    return false
  }

  const { releases } = linuxReleasesResponse
  const latestRelease = releases.find((r) =>
    r.version.match(stableReleasePattern)
  )

  const fs = require('fs')
  const data = fs.readFileSync(resultPath, 'utf8')
  const oldJson = JSON.parse(data)

  const { version, channel, hash: commit } = latestRelease

  if (data.flutter.version === version) {
    core.info(`Flutter version ${version} is already set.`)

    return false
  }

  // Update result file, i.e. version.json
  const newJson = {
    ...oldJson,
    flutter: {
      channel,
      commit,
      version,
    },
  }

  // Write outputs
  resultJson = JSON.stringify(newJson, null, 4)
  fs.writeFileSync(resultPath, `${resultJson}\n`)
  core.exportVariable('FLUTTER_VERSION', version)

  return true
}

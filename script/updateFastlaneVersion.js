module.exports = async ({ core, fetch }) => {
  const versionFileUrl =
    'https://rubygems.org/api/v1/versions/fastlane/latest.json'

  let version
  try {
    const response = await fetch(versionFileUrl)

    const data = await response.json()
    
    version = data.version
  } catch (error) {
    console.error(
      `An error occurred while requesting the file URL: ${versionFileUrl}`,
      error
    )

    return false
  }

  if (version === undefined) {
    core.setFailed(`Fastlane version URL ${versionFileUrl} doesn't exist`)

    return false
  }

  // Update result file, i.e. version.json
  const resultPath = 'config/version.json'
  const data = fs.readFileSync(resultPath, 'utf8')
  const json = JSON.parse(data)

  const result = {
    ...json,
    fastlane: {
      version,
    },
  }

  fs.writeFileSync(resultPath, JSON.stringify(result, null, 4))
}

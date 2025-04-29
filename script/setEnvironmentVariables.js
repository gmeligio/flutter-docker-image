module.exports = async ({ core }) => {
  const { VERSION_MANIFEST, GITHUB_REPOSITORY_OWNER, IMAGE_REPOSITORY_NAME } =
    process.env

  if (!VERSION_MANIFEST) {
    core.setFailed('Environment variable VERSION_MANIFEST is required.')
    return false
  }

  if (!GITHUB_REPOSITORY_OWNER) {
    core.setFailed('Environment variable GITHUB_REPOSITORY_OWNER is required.')
    return false
  }

  if (!IMAGE_REPOSITORY_NAME) {
    core.setFailed('Environment variable IMAGE_REPOSITORY_NAME is required.')
    return false
  }

  const fs = require('fs')
  const text = fs.readFileSync(VERSION_MANIFEST, 'utf8')
  const data = JSON.parse(text)

  const platforms = data.android.platforms
    .map((platform) => platform.version)
    .join(' ')

  core.exportVariable('FLUTTER_VERSION', data.flutter.version)
  core.exportVariable(
    'ANDROID_BUILD_TOOLS_VERSION',
    data.android.buildTools.version
  )
  core.exportVariable('ANDROID_PLATFORM_VERSIONS', platforms)
  core.exportVariable('ANDROID_NDK_VERSION', data.android.ndk.version)
  core.exportVariable('CMAKE_VERSION', data.android.cmake.version)
  core.exportVariable(
    'IMAGE_REPOSITORY_PATH',
    `${GITHUB_REPOSITORY_OWNER}/${IMAGE_REPOSITORY_NAME}`
  )

  return true
}

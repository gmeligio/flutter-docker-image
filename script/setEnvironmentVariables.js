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

  // Reading through this helper rather than dotting into `data` directly means a
  // renamed or removed manifest field fails here, naming the path, instead of
  // exporting `undefined` and surfacing 15 minutes later as an empty ARG — or
  // not at all, since the `web` stage declares none of these arguments.
  const read = (path) => {
    const value = path
      .split('.')
      .reduce((node, key) => (node == null ? node : node[key]), data)

    if (value === undefined || value === null) {
      throw new Error(
        `${VERSION_MANIFEST} has no value at '${path}'. ` +
          'Add the field, or remove the export that reads it.'
      )
    }

    return value
  }

  let exports
  try {
    exports = {
      FLUTTER_VERSION: read('flutter.version'),
      FASTLANE_VERSION: read('fastlane.version'),
      ANDROID_BUILD_TOOLS_VERSION: read('android.buildTools.version'),
      ANDROID_JAVA_VERSION: read('android.java.version'),
      ANDROID_PLATFORM_VERSIONS: read('android.platforms')
        .map((platform) => platform.version)
        .join(' '),
      ANDROID_NDK_VERSION: read('android.ndk.version'),
      CMAKE_VERSION: read('android.cmake.version'),
      GIT_VERSION: read('windows.git.version'),
      VS_CMAKE_VERSION: read('windows.vsBuildTools.cmakeProject.version'),
      VS_WIN11SDK_BUILD: read('windows.vsBuildTools.windows11Sdk.build'),
      VS_VCTOOLS_VERSION: read('windows.vsBuildTools.vcTools.version'),
    }
  } catch (error) {
    core.setFailed(error.message)
    return false
  }

  for (const [name, value] of Object.entries(exports)) {
    core.exportVariable(name, value)
  }

  core.exportVariable(
    'IMAGE_REPOSITORY_PATH',
    `${GITHUB_REPOSITORY_OWNER}/${IMAGE_REPOSITORY_NAME}`
  )

  // Once the build legs stop listing build arguments inline, this log is where a
  // job run records which manifest values it actually built with.
  core.startGroup(`Versions read from ${VERSION_MANIFEST}`)
  for (const [name, value] of Object.entries(exports)) {
    core.info(`${name}=${value}`)
  }
  core.endGroup()

  return true
}

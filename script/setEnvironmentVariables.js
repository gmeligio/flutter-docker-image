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

  // Backstop only. config/schema.cue is the real guard and also checks semver
  // shapes, but runs in a separate step — these throws are the last chance
  // before a bad value becomes a build arg.
  const isBlank = (value) =>
    value === undefined || value === null || value === ''

  const read = (path) => {
    const value = path
      .split('.')
      .reduce((node, key) => (node == null ? node : node[key]), data)

    if (isBlank(value)) {
      throw new Error(`${VERSION_MANIFEST} has no value at '${path}'.`)
    }

    return value
  }

  const readPlatformVersions = () => {
    const platforms = read('android.platforms')

    if (!Array.isArray(platforms) || platforms.length === 0) {
      throw new Error(
        `${VERSION_MANIFEST} needs a non-empty array at 'android.platforms'.`
      )
    }

    return platforms
      .map((platform, index) => {
        if (isBlank(platform?.version)) {
          throw new Error(
            `${VERSION_MANIFEST} has no value at 'android.platforms[${index}].version'.`
          )
        }

        return platform.version
      })
      .join(' ')
  }

  let exports
  try {
    exports = {
      FLUTTER_VERSION: read('flutter.version'),
      FASTLANE_VERSION: read('fastlane.version'),
      ANDROID_BUILD_TOOLS_VERSION: read('android.buildTools.version'),
      ANDROID_JAVA_VERSION: read('android.java.version'),
      ANDROID_PLATFORM_VERSIONS: readPlatformVersions(),
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

  // The only run-level record of what a build actually used.
  core.startGroup(`Versions read from ${VERSION_MANIFEST}`)
  for (const [name, value] of Object.entries(exports)) {
    core.info(`${name}=${value}`)
  }
  core.endGroup()

  return true
}

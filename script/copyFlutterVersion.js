const fs = require('fs')
const path = require('path')

module.exports = async ({ core }) => {
  try {
    const flutterVersionPath = 'config/flutter_version.json'

    if (
      !fs.existsSync(flutterVersionPath) ||
      fs.lstatSync(flutterVersionPath).isDirectory()
    ) {
      throw new Error(`${flutterVersionPath} is missing or is a directory.`)
    }

    const flutterVersionData = fs.readFileSync(flutterVersionPath, 'utf8')
    const flutterVersionJson = JSON.parse(flutterVersionData)

    const versionPath = 'config/version.json'
    if (
      !fs.existsSync(versionPath) ||
      fs.lstatSync(versionPath).isDirectory()
    ) {
      throw new Error(`${versionPath} is missing or is a directory.`)
    }

    const versionData = fs.readFileSync(versionPath, 'utf8')
    let versionJson = JSON.parse(versionData)

    const resultPath = 'config/version.json'
    const result = {
      ...versionJson,
      ...flutterVersionJson,
    }

    const resultJson = JSON.stringify(result, null, 4)
    fs.writeFileSync(resultPath, `${resultJson}\n`)

    const version = flutterVersionJson.flutter.version
    const channel = flutterVersionJson.flutter.channel

    core.exportVariable('FLUTTER_VERSION', version)
    core.exportVariable('FLUTTER_CHANNEL', channel)
  } catch (error) {
    core.setFailed(`Error in copyFlutterVersion script: ${error.message}`)
  }
}

module.exports = async ({ core}) => {
  const fs = require('fs')
  
  const flutterVersionPath = 'config/flutter_version.json'
  const flutterVersionData = fs.readFileSync(flutterVersionPath, 'utf8')
  const fluterVersionJson = JSON.parse(flutterVersionData)
  
  const versionPath = 'config/version.json'
  const versionData = fs.readFileSync(versionPath, 'utf8')
  let versionJson = JSON.parse(versionData)

  const resultPath = 'config/version.json'

  const result = {
    ...versionJson,
    ...fluterVersionJson,
  }

  fs.writeFileSync(resultPath, JSON.stringify(result, null, 4))

  const version = fluterVersionJson.flutter.version
  const channel = fluterVersionJson.flutter.channel

  // Export FLUTTER_VERSION and FLUTTER_CHANNEL for the next workflow steps
  core.exportVariable('FLUTTER_VERSION', version)
  core.exportVariable('FLUTTER_CHANNEL', channel)
}

#!/usr/bin/env node
// Code-generates readme.md from config/version.json. Node standard library only
// (no dependencies). Run via `mise run docs`; CI re-runs it and fails if the
// committed readme.md drifts (git diff --exit-code). The same readme.md is used
// as the GitHub README and the Docker Hub description.
//
// Covers both published Linux images (flutter-android, flutter-web) and renders
// the per-image "Main tools" lists required by the image-tool-inventory spec.
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const v = JSON.parse(readFileSync(resolve(root, 'config/version.json'), 'utf8'))

// ---- values mapped from version.json (single source of truth) --------------
const owner = 'gmeligio'
const flutter = v.flutter.version
const channel = v.flutter.channel
const channelColor = { stable: 'blue', beta: 'orange', dev: 'red', master: 'red' }[channel] ?? 'blue'
const android = {
  java: v.android.java.version,
  platforms: v.android.platforms.map((p) => p.version).join(', '),
  ndk: v.android.ndk.version,
  gradle: v.android.gradle.version,
  buildTools: v.android.buildTools.version,
  fastlane: v.fastlane.version,
}

const repo = (name) => `${owner}/${name}`
const tag = (name) => `${repo(name)}:${flutter}`
const ghcr = (name) => `ghcr.io/${tag(name)}`

// ---- helpers ---------------------------------------------------------------
const slug = (s) => s.toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-')

// GitHub-style table of contents from ## / ### headings, skipping code fences.
function toc(md) {
  let inFence = false
  const out = []
  for (const line of md.split('\n')) {
    if (/^```/.test(line)) { inFence = !inFence; continue }
    if (inFence) continue
    const m = line.match(/^(#{2,3})\s+(.*)/)
    if (!m) continue
    const [, hashes, text] = m
    out.push(`${'  '.repeat(hashes.length - 2)}* [${text}](#${slug(text)})`)
  }
  return out.join('\n')
}

const dockerBadge = (name, kind, label) =>
  `[![${name} ${kind}](https://img.shields.io/docker/${kind === 'version' ? 'v' : 'pulls'}/${repo(name)}?label=${encodeURIComponent(label)})](https://hub.docker.com/r/${repo(name)}/tags)`

const registryTable = (name) =>
  [
    `| Registry                  | ${name} |`,
    `| ------------------------- | ${'-'.repeat(Math.max(name.length, 15))} |`,
    `| Docker Hub                | [${tag(name)}](https://hub.docker.com/r/${repo(name)}) |`,
    `| GitHub Container Registry | [${ghcr(name)}](https://github.com/${owner}/flutter-docker-image/pkgs/container/${name}) |`,
    `| Quay                      | [quay.io/${tag(name)}](https://quay.io/repository/${repo(name)}) |`,
  ].join('\n')

const ghWorkflow = (name, buildCmd) =>
  ['```yaml', 'jobs:', '  build:', '    runs-on: ubuntu-22.04', '    container:',
   `      image: ${ghcr(name)}`, '    steps:', '      - name: Checkout',
   '        uses: actions/checkout@v4', '      - name: Build', `        run: ${buildCmd}`, '```'].join('\n')

// ---- badges ----------------------------------------------------------------
const badges = [
  `[![openssf scorecard](https://api.scorecard.dev/projects/github.com/${owner}/flutter-docker-image/badge)](https://scorecard.dev/viewer/?uri=github.com/${owner}/flutter-docker-image)`,
  `[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/${owner}/flutter-docker-image)`,
  `[![channel](https://img.shields.io/static/v1?label=channel&message=${channel}&color=${channelColor})](https://docs.flutter.dev/release/archive?tab=linux)`,
  dockerBadge('flutter-android', 'version', 'flutter-android version'),
  dockerBadge('flutter-android', 'pulls', 'flutter-android pulls'),
  dockerBadge('flutter-web', 'version', 'flutter-web version'),
  dockerBadge('flutter-web', 'pulls', 'flutter-web pulls'),
].join(' ')

// ---- body ------------------------------------------------------------------
const body = `## Features

* Analytics disabled by default, opt-in if \`ENABLE_ANALYTICS\` environment variable is passed when running the container.
* Rootless user \`flutter:flutter\`, with permissions to run on GitHub workflows and GitLab CI.
* Minimal images with predownloaded SDKs and tools ready to run \`flutter\` commands without further downloads:
  * \`flutter-android\` for the Android platform.
  * \`flutter-web\` for the Web platform.

Main tools in \`flutter-android\`:

* Flutter SDK: ${flutter}
* Java (OpenJDK): ${android.java}
* Android SDK Platform: ${android.platforms}
* Android NDK: ${android.ndk}
* Gradle: ${android.gradle}
* Fastlane: ${android.fastlane}

Main tools in \`flutter-web\`:

* Flutter SDK: ${flutter}
* Web engine: precached (no runtime download)

## Running Containers

${registryTable('flutter-android')}

On the terminal:

\`\`\`bash
# From GitHub Container Registry
docker run --rm -it ${ghcr('flutter-android')} bash
\`\`\`

On a workflow in GitHub Actions:

${ghWorkflow('flutter-android', 'flutter build apk')}

On a \`.gitlab-ci.yml\` in GitLab CI:

\`\`\`yaml
build:
  image: ${ghcr('flutter-android')}
  script:
    - flutter build apk
\`\`\`

For Flutter web apps, use the \`flutter-web\` image:

${registryTable('flutter-web')}

${ghWorkflow('flutter-web', 'flutter build web')}

These images run on GitHub Actions, GitLab CI, Gitea, and Forgejo. Ready-to-use
workflows for each backend are in [\`examples/\`](examples/) — the Gitea and Forgejo
ones show how to make Node.js available for \`actions/checkout\` (act-based runners
do not inject it the way GitHub does).

## Tags

Every new tag on the flutter stable channel gets built. The tag is composed of the Flutter version used to build the image:

* Docker image: ${tag('flutter-android')}
* Flutter version: ${flutter}

## Building Locally

The android.Dockerfile expects a few arguments:

* \`flutter_version <string>\`: The version of Flutter to use when building. Example: ${flutter}
* \`android_build_tools_version <string>\`: The version of the Android SDK Build Tools to install. Example: ${android.buildTools}
* \`android_platform_versions <list>\`: The versions of the Android SDK Platforms to install, separated by spaces. Example: ${android.platforms}

\`\`\`bash
# Android
docker build --target android --build-arg flutter_version=${flutter} --build-arg fastlane_version=${android.fastlane} --build-arg android_build_tools_version=${android.buildTools} --build-arg android_platform_versions="${android.platforms}" -t android-test .
\`\`\`

## Roadmap

* Minimal image with predownloaded SDKs and tools ready to run \`flutter\` commands for the platforms:
  * iOS
  * Linux
  * Windows
* Android features:
  * Android emulator

## FAQ

### Why the images are not published in the AWS ECR Public registry?

The storage of the images starts to cost after 50 GB and increases with every pushed image because the AWS Free Tier covers up to 50 GB of total storage for free in ECR Public.

### Why there is no dynamic tag like \`latest\`?

There is no \`latest\` Docker tag on purpose. You need to specify the version of the image you want to use. The reason for that is that \`latest\` can cause unexpected behavior when rerunning a past CI job that was expected to use the old build of the \`latest\` tag. There are multiple articles explaining more about this reasoning like [What's Wrong With The Docker :latest Tag?](https://vsupalov.com/docker-latest-tag/) and [The misunderstood Docker tag: latest](https://medium.com/@mccode/the-misunderstood-docker-tag-latest-af3babfd6375).

## Contributing

See [Contributing](docs/contributing.md).

## License

Flutter is licensed under [BSD 3-Clause "New" or "Revised" license](https://github.com/flutter/flutter/blob/master/LICENSE).

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.

The [sources](https://github.com/${owner}/flutter-docker-image) for producing ${repo('flutter-android')} Docker images are licensed under [MIT License](LICENSE.md).`

const readme = `<!--- This markdown file was auto-generated from docs/build.mjs -->

${badges}

# Flutter Docker Image

Docker images for Flutter Continuous Integration (CI). The source is available [on GitHub](https://github.com/${owner}/flutter-docker-image).

The images includes the minimum tools to run Flutter and build apps. The versions of the tools installed are based on the official [Flutter](https://github.com/flutter/flutter) repository. The final goal is that Flutter doesn't need to download anything like tools or SDKs when running the container.

## Contents

${toc(body)}

${body}
`

writeFileSync(resolve(root, 'readme.md'), readme)
console.log('📝 readme.md')

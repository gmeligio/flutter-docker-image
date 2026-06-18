#!/usr/bin/env node
// Code-generates readme.md from config/version.json. Node standard library only
// (no dependencies). Run via `mise run docs`; CI re-runs it and fails if the
// committed readme.md drifts (git diff --exit-code). The same readme.md is used
// as the GitHub README and the Docker Hub description.
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, resolve } from 'node:path'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const v = JSON.parse(readFileSync(resolve(root, 'config/version.json'), 'utf8'))

// ---- the one place mapping version.json -> documentation values ------------
const repo = 'gmeligio/flutter-android'
const tag = `${repo}:${v.flutter.version}`
const ghcr = `ghcr.io/${tag}`
const platforms = v.android.platforms.map((p) => p.version).join(', ')
const channel = v.flutter.channel
const channelColor = { stable: 'blue', beta: 'orange', dev: 'red', master: 'red' }[channel] ?? 'blue'

// ---- helpers ---------------------------------------------------------------
const slug = (s) => s.toLowerCase().replace(/[^\w\s-]/g, '').trim().replace(/\s+/g, '-')

// Build a GitHub-style table of contents from the ## / ### headings of `md`,
// skipping anything inside fenced code blocks.
function toc(md) {
  let inFence = false
  const out = []
  for (const line of md.split('\n')) {
    if (/^```/.test(line)) { inFence = !inFence; continue }
    if (inFence) continue
    const m = line.match(/^(#{2,3})\s+(.*)/)
    if (!m) continue
    const [, hashes, text] = m
    out.push(`${'  '.repeat(hashes.length - 2)}- [${text}](#${slug(text)})`)
  }
  return out.join('\n')
}

// ---- content (composed in code; values injected from version.json) ---------
const badges = [
  `[![openssf scorecard](https://api.scorecard.dev/projects/github.com/gmeligio/flutter-docker-image/badge)](https://scorecard.dev/viewer/?uri=github.com/gmeligio/flutter-docker-image)`,
  `[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/gmeligio/flutter-docker-image)`,
  `[![channel](https://img.shields.io/static/v1?label=channel&message=${channel}&color=${channelColor})](https://docs.flutter.dev/release/archive?tab=linux)`,
  `[![flutter-android version](https://img.shields.io/docker/v/${repo}?label=flutter-android%20version)](https://hub.docker.com/r/${repo}/tags)`,
  `[![flutter-android pulls](https://img.shields.io/docker/pulls/${repo}?label=flutter-android%20pulls)](https://hub.docker.com/r/${repo}/tags)`,
].join(' ')

const body = `## Features

- Installed Flutter SDK ${v.flutter.version}.
- Analytics disabled by default, opt-in if \`ENABLE_ANALYTICS\` environment variable is passed when running the container.
- Rootless user \`flutter:flutter\`, with permissions to run on GitHub workflows and GitLab CI.
- Cached Fastlane gem ${v.fastlane.version}.
- Minimal image with predownloaded SDKs and tools ready to run \`flutter\` commands for the Android platform.

Predownloaded SDKs and tools in Android:

- Licenses accepted
- Android SDK Platforms: ${platforms}
- Android NDK: ${v.android.ndk.version}
- Gradle: ${v.android.gradle.version}

## Running Containers

| Registry                  | flutter-android |
| ------------------------- | --------------- |
| Docker Hub                | [${tag}](https://hub.docker.com/r/${repo}) |
| GitHub Container Registry | [${ghcr}](https://github.com/gmeligio/flutter-docker-image/pkgs/container/flutter-android) |
| Quay                      | [quay.io/${tag}](https://quay.io/repository/${repo}) |

On the terminal:

\`\`\`bash
# From GitHub Container Registry
docker run --rm -it ${ghcr} bash
\`\`\`

On a workflow in GitHub Actions:

\`\`\`yaml
jobs:
  build:
    runs-on: ubuntu-22.04
    container:
      image: ${ghcr}
    steps:
      - name: Checkout
        uses: actions/checkout@v4
      - name: Build
        run: flutter build apk
\`\`\`

On a \`.gitlab-ci.yml\` in GitLab CI:

\`\`\`yaml
build:
  image: ${ghcr}
  script:
    - flutter build apk
\`\`\`

This image runs on GitHub Actions, GitLab CI, Gitea, and Forgejo. Ready-to-use
workflows for each are in [\`examples/\`](examples/) — the Gitea and Forgejo ones
show how to make Node.js available for \`actions/checkout\` (act-based runners do
not inject it the way GitHub does).

Fastlane:

\`\`\`bash
# Ruby bundler is available in the container.
# The fastlane gem is cached but not installed
# For more information, see https://docs.fastlane.tools

# Use --prefer-local to download gems only if they are not cached
bundle install --prefer-local
bundle exec fastlane
\`\`\`

## Tags

Every new tag on the flutter stable channel gets built. The tag is composed of the Flutter version used to build the image:

- Docker image: ${tag}
- Flutter version: ${v.flutter.version}

## Building Locally

The android.Dockerfile expects a few arguments:

- \`flutter_version <string>\`: The version of Flutter to use when building. Example: ${v.flutter.version}
- \`android_build_tools_version <string>\`: The version of the Android SDK Build Tools to install. Example: ${v.android.buildTools.version}
- \`android_platform_versions <list>\`: The versions of the Android SDK Platforms to install, separated by spaces. Example: ${platforms}

\`\`\`bash
# Android
docker build --target android --build-arg flutter_version=${v.flutter.version} --build-arg fastlane_version=${v.fastlane.version} --build-arg android_build_tools_version=${v.android.buildTools.version} --build-arg android_platform_versions="${platforms}" -t android-test .
\`\`\`

## Roadmap

- Minimal image with predownloaded SDKs and tools ready to run \`flutter\` commands for the platforms:
  - iOS
  - Linux
  - Windows
  - Web
- Android features:
  - Android emulator

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

The [sources](https://github.com/gmeligio/flutter-docker-image) for producing ${repo} Docker images are licensed under [MIT License](LICENSE.md).`

const readme = `<!--- This markdown file was auto-generated from docs/build.mjs -->

${badges}

# Flutter Docker Image

Docker images for Flutter Continuous Integration (CI). The source is available [on GitHub](https://github.com/gmeligio/flutter-docker-image).

The images includes the minimum tools to run Flutter and build apps. The versions of the tools installed are based on the official [Flutter](https://github.com/flutter/flutter) repository. The final goal is that Flutter doesn't need to download anything like tools or SDKs when running the container.

## Contents

${toc(body)}

${body}
`

writeFileSync(resolve(root, 'readme.md'), readme)
console.log('📝 readme.md')

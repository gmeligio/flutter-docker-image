#!/usr/bin/env node
// Code-generates readme.md from config/version.json. Node standard library only
// (no dependencies). Run via `mise run docs`; CI re-runs it and fails if the
// committed readme.md drifts (git diff --exit-code). The same readme.md is used
// as the GitHub README and the Docker Hub description.
//
// Covers every published image (flutter-android, flutter-web, flutter-windows)
// as a concise quick-start: what-is / how-to-use above the fold. Reference and
// contributor material lives in static docs/ pages, linked from the README.
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

const repo = (name) => `${owner}/${name}`
const tag = (name) => `${repo(name)}:${flutter}`
const ghcr = (name) => `ghcr.io/${tag(name)}`

// ---- helpers ---------------------------------------------------------------
// Docker Hub pull-count badge. All images share the manifest Flutter version, so
// the version is a single static badge (below), not one docker/v badge per image.
const pullsBadge = (name, label) =>
  `[![${name} pulls](https://img.shields.io/docker/pulls/${repo(name)}?label=${encodeURIComponent(label)})](https://hub.docker.com/r/${repo(name)}/tags)`

// One registry table covering every image: rows are registries, columns are
// the images. Cells are per-registry pull references, so the three images share
// a single table instead of repeating Docker Hub / GHCR / Quay once each.
const images = ['flutter-android', 'flutter-web', 'flutter-windows']
const registryTable = () => {
  const dockerHub = (name) => `[${tag(name)}](https://hub.docker.com/r/${repo(name)})`
  const githubCR = (name) => `[${ghcr(name)}](https://github.com/${owner}/flutter-docker-image/pkgs/container/${name})`
  const quay = (name) => `[quay.io/${tag(name)}](https://quay.io/repository/${repo(name)})`
  const row = (label, cell) => `| ${label} | ${images.map(cell).join(' | ')} |`
  return [
    `| Registry | ${images.join(' | ')} |`,
    `| --- | ${images.map(() => '---').join(' | ')} |`,
    row('Docker Hub', dockerHub),
    row('GitHub Container Registry', githubCR),
    row('Quay', quay),
  ].join('\n')
}

const ghWorkflow = (name, buildCmd) =>
  ['```yaml', 'jobs:', '  build:', '    runs-on: ubuntu-22.04', '    container:',
   `      image: ${ghcr(name)}`, '    steps:', '      - name: Checkout',
   '        uses: actions/checkout@v4', '      - name: Build', `        run: ${buildCmd}`, '```'].join('\n')

// Windows containers cannot run under the Linux `container:` field, so the
// flutter-windows job runs on a windows-2025 runner and invokes docker directly.
const windowsWorkflow = (buildCmd) =>
  ['```yaml', 'jobs:', '  build:', '    runs-on: windows-2025', '    steps:',
   '      - name: Checkout', '        uses: actions/checkout@v4', '      - name: Build',
   `        run: docker run --rm -v \${{ github.workspace }}:C:\\app -w C:\\app ${ghcr('flutter-windows')} ${buildCmd}`,
   '```'].join('\n')

// ---- badges ----------------------------------------------------------------
const badges = [
  `[![openssf scorecard](https://api.scorecard.dev/projects/github.com/${owner}/flutter-docker-image/badge)](https://scorecard.dev/viewer/?uri=github.com/${owner}/flutter-docker-image)`,
  `[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/${owner}/flutter-docker-image)`,
  `[![version](https://img.shields.io/static/v1?label=version&message=${flutter}&color=blue)](https://docs.flutter.dev/release/archive?tab=linux)`,
  `[![channel](https://img.shields.io/static/v1?label=channel&message=${channel}&color=${channelColor})](https://docs.flutter.dev/release/archive?tab=linux)`,
  pullsBadge('flutter-android', 'flutter-android pulls'),
  pullsBadge('flutter-web', 'flutter-web pulls'),
  pullsBadge('flutter-windows', 'flutter-windows pulls'),
].join(' ')

// ---- body ------------------------------------------------------------------
const body = `Minimal Docker images for building Flutter apps in Continuous Integration (CI), for Android, Web, and Windows platforms, with the SDK and toolchain predownloaded so \`flutter\` runs without extra downloads. Images track the Flutter **stable** channel and the current version is **${flutter}**.

\`\`\`bash
docker run --rm -it ${ghcr('flutter-android')} flutter build apk
\`\`\`

Each image is tagged with the Flutter version it ships (\`:${flutter}\`), there is no \`latest\` tag ([see more on the why](docs/faq.md#why-there-is-no-dynamic-tag-like-latest)). All tools running in the image have analytics disabled and opt-in with \`ENABLE_ANALYTICS=true\`, and a rootless \`flutter:flutter\` user.

## Registries

Every image is published to three registries under the same \`:${flutter}\` tag:

${registryTable()}

## GitHub Actions

The Linux images (\`flutter-android\`, \`flutter-web\`) run as the job container:

${ghWorkflow('flutter-android', 'flutter build apk')}

Swap the image and build command for \`flutter-web\` (\`flutter build web\`). Windows containers cannot run under the Linux \`container:\` field, so \`flutter-windows\` runs on a \`windows-2025\` runner and invokes \`docker\` directly:

${windowsWorkflow('flutter build windows')}

## CI backends

These images run on GitHub Actions, GitLab CI, Gitea, and Forgejo. See example workflows for each backend in [\`examples/\`](examples/).

## More

* [Building the images locally](docs/contributing.md#building-the-images-locally)
* [FAQ](docs/faq.md)
* [Contributing](docs/contributing.md)

## License

Flutter is licensed under [BSD 3-Clause "New" or "Revised" license](https://github.com/flutter/flutter/blob/master/LICENSE).

As with all Docker images, these likely also contain other software which may be under other licenses (such as Bash, etc from the base distribution, along with any direct or indirect dependencies of the primary software being contained).

As for any pre-built image usage, it is the image user's responsibility to ensure that any use of this image complies with any relevant licenses for all software contained within.

The [sources](https://github.com/${owner}/flutter-docker-image) for producing these Docker images are licensed under [MIT License](LICENSE.md).`

const readme = `<!--- This markdown file was auto-generated from docs/build.mjs -->

${badges}

# Flutter Docker Image

${body}
`

writeFileSync(resolve(root, 'readme.md'), readme)
console.log('📝 readme.md')

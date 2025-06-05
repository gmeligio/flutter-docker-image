# Changelog

All notable changes to this project will be documented in this file.

## [3.32.2] - 2025-06-05

### ⚙️ Miscellaneous Tasks

- Split  into tag.yml and changelog.yml workflows (#347)
- *(release)* Update flutter dependencies in version.json for 3.32.2 (#348)

## [3.32.1] - 2025-05-30

### ⚙️ Miscellaneous Tasks

- *(release)* Update flutter dependencies in version.json for 3.32.1 (#345)

## [3.32.0] - 2025-05-23

### ⚙️ Miscellaneous Tasks

- Generate changelog with git-cliff (#330)
- Set tools digest to verify integrity (#331)
- Download immutable artifact by id (#337)
- Update artifact download configuration (#342)
- *(release)* Update flutter dependencies in version.json for 3.32.0 (#343)

## [3.29.3] - 2025-04-17

### 🚀 Features

- Build windows image (#314)

### 🐛 Bug Fixes

- *(deps)* Update dependency mdx-to-md to ^0.5.0 (#324)

### 💼 Other

- *(deps)* Bump @babel/runtime (#312)
- Update windows image to ltsc2025 (#317)
- *(deps)* Bump estree-util-value-to-estree from 3.3.2 to 3.3.3 in /docs/src in the npm_and_yarn group across 1 directory (#325)

### 📚 Documentation

- Add table of contents and image table (#323)

### ⚙️ Miscellaneous Tasks

- Single workflow to update versions (#311)
- Get version from parsed JSON (#313)
- Schedule GitHub Actions updates on the first day of the month (#318)
- Upgrade artifact actions to use digest (#319)
- Grant app token only  current repository (#320)
- Download-artifact can not overwrite existing files (#327)
- Path is a folder in download-artifact (#328)
- Update flutter dependencies in version.json for 3.29.3 (#329)

## [3.29.2] - 2025-03-15

### ⚙️ Miscellaneous Tasks

- Generate tag with Github App token to trigger Actions (#305)
- Run pr build only from latest commit (#306)
- Upgrade actions only for new major or minor versions (#308)
- Update flutter version in flutter_version.json to 3.29.2 (#309)
- Update flutter dependencies in version.json for 3.29.2 (#310)

## [3.29.1] - 2025-03-09

### 🐛 Bug Fixes

- Use github context because octokit is not available (#293)

### 💼 Other

- Replace yq with cue to reduce tool dependencies (#296)

### 📚 Documentation

- Mention Flutter license (#301)

### ⚙️ Miscellaneous Tasks

- Split ci and release workflows (#291)
- Checkout repository (#292)
- Read environment variables in create_git_tag (#294)
- Define VERSION_MANIFEST at workflow level (#295)
- Replace jq with cue to reduce tool dependencies (#297)
- Use deb renovate datasource instead of repology (#300)
- Update flutter version in flutter_version.json to 3.29.1 (#302)
- Discard changes to flutter source code when switching tags (#303)
- Update flutter dependencies in version.json for 3.29.1 (#304)

## [3.29.0] - 2025-02-17

### 🐛 Bug Fixes

- Update version.json path
- Remove annotation CompileDynamic
- Remove ecr registry
- Don't print message on entrypoint to allow initial calls from CI systems (#155)

### 💼 Other

- Move Dockerfile to root
- Remove locale env and update regex and update git version
- Create flutter base image and then android
- Set non-root user as flutter
- Flutter downloads obsolete Android SDK Tools (revision: 26.1.1)
- Add entrypoint to change ownership of CI_PROJECT_DIR
- Leave sudo but remove entrypoint
- Add logical and before modifying sudoers
- Add pattern /builds/* to sudoers
- Add image opencontainers labels
- Set JAVA_HOME
- Explicitly set java home
- Join env statements
- Add multiple platform versions
- Use platforms_versions
- Do not quote array of arguments in build args
- Upgrade curl to 7.81.0-1ubuntu1.8
- Upgrade openjdk-11-jdk to 11.0.18+10-0ubuntu1~22.04 and sudo to 1.9.9-1ubuntu2.2
- Add ENABLE_ANALYTICS to entrypoint
- Upgrade curl to 7.81.0-1ubuntu1.10
- Update sudo to 1.9.9-1ubuntu2.4
- Add repology source ubuntu 22:04
- Remove os specifc versioning
- Fix typo between curl and git
- Fix ubuntu package names
- Upgrade git to 2.34.1-1ubuntu1.8
- Add args for openjdk and sudo
- Make entrypoint executable
- Copy entrypoint with flutter user permissions
- Upgrade openjdk-11-jdk to 11.0.19+7~us1-0ubuntu1~22.04.1
- Chmod entrypoint
- Migrate to openjdk-11-jdk-headless
- Migrate to JRE with openjdk-11-jre-headless
- Restore openjdk-11-jdk-headless
- Uncomment flutter installation
- Switch to debian/debian:11-slim
- Add cross-env
- Add fastlane stage
- Install fastlane with bundler
- Update dependencies versions in manifest with flutter 3.13.0' (#33)
- Upgrade to openjdk 17 to 17.0.7+7-1~deb11u1 (#37)
- Upgrade to debian 12 (#78)
- Change debian registry to docker hub (#90)
- Upgrade openjdk-17-jdk-headless to 17.0.10+7-1~deb12u1 (#158)
- Join parsed platform versions with space
- *(deps)* Bump braces (#196)
- *(deps)* Bump cross-spawn from 7.0.3 to 7.0.6 in /docs/src in the npm_and_yarn group across 1 directory (#267)
- *(deps)* Bump esbuild (#285)
- Remove --depth 1 from git clone in Dockerfile (#287)

### 🚜 Refactor

- Format version.json with prettier
- Update renovate according to validator (#122)
- Migrate Android version update script to Kotlin DSL and remove Groovy version (#288)

### 📚 Documentation

- Add todo to get latest versions
- Clarify readme
- Leave registry link only
- Add mdx readme
- Update readme.mdx
- Add license
- Add url to badges
- Delete images.json
- Reorganize readme
- Mention gitlab ci yaml
- Render docs
- Update tool versions
- Rename usage to getting started
- Add source repository
- Reorganize readme
- Add interpolating expressions and className to code blocks
- Replace triple backtick with pre code block to remove exceeding line
- Delete unused sha from readme
- Explain more why not latest
- Split readme and ecr about
- Add fastlane related project
- Change wording of related projects
- Remove todo URLs from Dockerfile
- Add command to render both docs
- Add channel badge
- Update android badges
- Add space after first badge
- Use .com github domain
- Group sections related to features (#42)
- Update documents (#233)
- Update license path (#234)
- Add a security policy (#238)
- Add openssf scorecard (#241)
- Reorganize sections in readme.md (#264)

### 🧪 Testing

- Add test_app
- Add test commands for downloads
- Increase timeout to 4m
- Verify analytics are disabled
- Check dart and flutter analytics are disabled
- Fastlane can run lanes
- Update expected android sdk command line tools to version 11.0 (#38)
- Gradle can have a patch version
- Platforms can have multiple versions

### ⚙️ Miscellaneous Tasks

- Add example workflow
- Sync after commit in vscode
- Move scripts to a new directory
- Build and push to ecr
- Add variable IMAGE_REPOSITORY_TAG
- Update scripts
- Give write permission to packages to github token
- Give read permission to contents to github token
- Use variables for container registries
- Use kaniko to build and push
- Upgrade flutter to 3.7.3
- Add --use-new-run to kaniko
- Use --snapshotMode=redo in kaniko
- Upgrade flutter to 3.7.4
- Add env variables FLUTTER_VERSION and ANDROID_BUILD_TOOLS_VERSION
- Add env variable PLATFORMS_VERSIONS
- Read version json
- Read version.json
- Add outputs
- Format echo
- Use release version in action zoexx/github-action-json-file-properties
- Echo all outputs
- Print all outputs
- Output only flutter
- FromJson version and commit
- Use fromJson in flutter_version
- Add github action for graphql
- Updating github-token to GH_API_TOKEN
- Log more output
- Keep only latest tag
- Unescape regex
- Write latest tag to file
- Add property node
- Read current version json
- Create pull request
- Add permissions for create pull request
- Add flutter version to tag
- Add variable env.FLUTTER_VERSION
- Setup flutter
- Use fromJson
- Create test app
- Running gradlew
- Add extension to updateAndroidPlatform.gradle
- Use forward slash for path separator
- Restore create pull request
- Clean test app
- Run on every day
- Push to docker hub
- Push to quay
- Load image metadata with docker/metadata-action
- Use raw tags in metadata
- Get last 20 tags to increase change of matching regex
- Add renovate
- Change ENV to ARG in renovate
- Disable docker major updates
- Disable docker minor update
- Pin version of ca-certificates
- Add version epoch to git ubuntu version
- Add environment variable GITHUB_SHORT_SHA
- Use snapshotMode redo in kaniko
- Update openjdk-11-jre-headless in renovate annotation
- Update gradle version
- Rename gradle script to updateAndroidVersions
- Delete unused test_app
- Show platform versions
- Use jq to extract variables from version.json
- Add xargs to convert multiline string to string with spaces
- Migrate to docker/build-push-action to allow testing image
- Setup buildx with docker/setup-buildx-action
- Use ghcr for image cache
- Test image structure
- Add build args and cache to local docker image
- Setup docker buildx before testing image
- Add target android
- Change path triggers
- Update docs after version
- Set the docs path to docs/src
- Add npm cache to documentation update job
- Change setup-node path
- Change working directory for update android versions
- Update docker hub description
- Fix gradle script path
- Update ecr repository description
- Use preinstalled jq in github actions
- Remove exceeding single quote
- Remove sha from tag
- Export flutter version from javascript
- Check in which channel the tag exists
- Remove semicolon
- Move github script to script directory
- Fix typo in script directory
- Reorganize files to clean root directory
- Add variable CACHE_REPOSITORY_PATH
- Rename android test to bundle test
- Update fastlane version
- Log version
- Await json
- Initialize data in js
- Require fs
- Increase tags returned from query to 60
- Add flutter-version to renovate.json
- Add flutter regex to renovate
- Use recursive matchStringsStrategy for flutter-version
- Escape dot in fileMatch regex
- Set config directory for flutter version
- Remove recursive strategy from renovate
- Split update workflow into flutter and dependencies
- Declare version variable
- Add workflow_dispatch trigger
- Correct flutter version to 3.10.6
- Update trigger to flutter_version
- Run update_flutter_dependencies after pr is merged
- Change automatic pr title
- Add other trigger to job if
- Move paths to pull request event (#31)
- Override version json with flutter version (#32)
- Use gitsign to sign commits in github workflows (#34)
- Add tag chainguard-dev/actions/setup-gitsign@main (#35)
- Update openjdk11 to 11.0.20+8-1~deb11u1 (#36)
- Use commit sha for github action versions (#39)
- Trigger workflow on push to main instead of pr closed (#41)
- Search in releases json file instead of github query (#43)
- LinuxReleasesResponse variable (#44)
- Use volta to reproduce nodejs version (#45)
- Get node version from package.json (#47)
- Merge old and new maps in gradle (#48)
- Use putAll to merge maps (#49)
- Validate json schema with cue (#50)
- Update dependencies versions in manifest with flutter 3.13.1 (#51)
- Update dependencies versions in manifest with flutter 3.13.1 (#54)
- Remove quote from pr title (#53)
- Update dependencies versions in manifest with flutter 3.13.2 (#57)
- Update dependencies versions in manifest with flutter 3.13.2 (#58)
- Update dependencies versions in manifest with flutter 3.13.3 (#62)
- Update dependencies versions in manifest with flutter 3.13.3 (#64)
- Pin cue-lang/setup-cue action to digest (#66)
- Update dependencies versions in manifest with flutter 3.13.4 (#72)
- Update dependencies versions in manifest with flutter 3.13.4 (#73)
- Add workflow for changes that affect the dockerfile (#77)
- Automerge chainguard digest changes (#79)
- Update dependencies versions in manifest with flutter 3.13.4 (#80)
- Change action host os to ubuntu-22.04 (#81)
- Change setup-flutter action to follow tag v2.2 (#82)
- Update dependencies versions in manifest with flutter 3.13.5 (#86)
- Update dependencies versions in manifest with flutter 3.13.5 (#87)
- Ignore .vscode folder (#89)
- Add renovate groups (#94)
- Update dependencies versions in manifest with flutter 3.13.6 (#95)
- Update dependencies versions in manifest with flutter 3.13.6 (#96)
- Rename jobs to separate status checks (#97)
- Update path of readme.md (#100)
- Update dependencies versions in manifest with flutter 3.13.7 (#101)
- Update dependencies versions in manifest with flutter 3.13.7 (#102)
- Update pull request titles created with action (#103)
- Update flutter version in flutter_version.json to 3.13.8 (#107)
- Use GH_APP_TOKEN to trigger workflows on created pull requests (#109)
- Update flutter dependencies in version.json for 3.13.8 (#108)
- Update flutter version in flutter_version.json to 3.13.9 (#112)
- Update flutter dependencies in version.json for 3.13.9 (#113)
- Update flutter version in flutter_version.json to 3.16.0 (#120)
- Update flutter dependencies in version.json for 3.16.0 (#121)
- Update flutter version in flutter_version.json to 3.16.1 (#129)
- Update flutter dependencies in version.json for 3.16.1 (#130)
- Update flutter version in flutter_version.json to 3.16.2 (#131)
- Update flutter dependencies in version.json for 3.16.2 (#132)
- Run renovate monthly (#134)
- Update flutter version in flutter_version.json to 3.16.3 (#135)
- Update flutter dependencies in version.json for 3.16.3 (#136)
- Update flutter version in flutter_version.json to 3.16.4 (#137)
- Update flutter dependencies in version.json for 3.16.4 (#138)
- Update flutter version in flutter_version.json to 3.16.5 (#139)
- Update flutter dependencies in version.json for 3.16.5 (#140)
- Update flutter version in flutter_version.json to 3.16.6 (#143)
- Update flutter dependencies in version.json for 3.16.6 (#144)
- Update flutter version in flutter_version.json to 3.16.7 (#145)
- Update flutter dependencies in version.json for 3.16.7 (#146)
- Update flutter version in flutter_version.json to 3.16.8 (#147)
- Update flutter dependencies in version.json for 3.16.8 (#148)
- Update flutter version in flutter_version.json to 3.16.9 (#149)
- Update flutter dependencies in version.json for 3.16.9 (#150)
- Run build if entrypoint changes (#156)
- Split config validation (#157)
- Check if files were changed (#159)
- Update flutter version in flutter_version.json to 3.19.0 (#160)
- Update flutter dependencies in version.json for 3.19.0 (#163)
- Update flutter version in flutter_version.json to 3.19.1 (#165)
- Update flutter dependencies in version.json for 3.19.1 (#166)
- Update flutter version in flutter_version.json to 3.19.2 (#167)
- Update flutter dependencies in version.json for 3.19.2 (#168)
- Update cron schedule to run only on weekdays (#173)
- Update flutter version in flutter_version.json to 3.19.3 (#174)
- Update flutter dependencies in version.json for 3.19.3 (#175)
- Update flutter version in flutter_version.json to 3.19.4 (#176)
- Update flutter dependencies in version.json for 3.19.4 (#177)
- Update flutter version in flutter_version.json to 3.19.5 (#178)
- Update flutter dependencies in version.json for 3.19.5 (#179)
- Update flutter version in flutter_version.json to 3.19.6 (#182)
- Update flutter dependencies in version.json for 3.19.6 (#183)
- Update flutter version in flutter_version.json to 3.22.0 (#186)
- Update flutter dependencies in version.json for 3.22.0 (#187)
- Update flutter version in flutter_version.json to 3.22.1 (#188)
- Update flutter dependencies in version.json for 3.22.1 (#189)
- Update flutter version in flutter_version.json to 3.22.2 (#192)
- Update flutter dependencies in version.json for 3.22.2 (#193)
- Update flutter dependencies in version.json for 3.22.2 (#197)
- Update flutter version in flutter_version.json to 3.22.3 (#202)
- Update flutter dependencies in version.json for 3.22.3 (#203)
- Update fastlane in version.json for 3.22.3 (#206)
- Upgrade peter-evans/create-pull-request to v6 (#207)
- Upgrade cue-lang/setup-cue to v1.0.1 (#208)
- Upgrade cue-lang/setup-cue to v1.0.1 in other workflows (#209)
- Update flutter version in flutter_version.json to 3.24.0 (#210)
- Update flutter dependencies in version.json for 3.24.0 (#211)
- Update flutter version in flutter_version.json to 3.24.1 (#212)
- Update flutter dependencies in version.json for 3.24.1 (#213)
- Use github integration for docker buildx cache (#218)
- Add docker/scout-action to compare differences (#219)
- Record only docker hub image (#220)
- Scout compare (#221)
- Pin docker/scount-action (#226)
- Update flutter version in flutter_version.json to 3.24.2 (#227)
- Run job in ghcr.io/gmeligio/flutter-android image (#228)
- Update flutter dependencies in version.json for 3.24.2 (#229)
- Update repo flutter version after pushing new image (#230)
- Update flutter version in flutter_version.json to 3.24.3 (#231)
- Update flutter dependencies in version.json for 3.24.3 (#232)
- Add scorecard (#235)
- Set default permission to contents:read (#236)
- Add CODEOWNERS (#237)
- Upload docker hub CVEs to code scanning (#239)
- Pin yq action with sha (#240)
- Show only fixable CVEs (#242)
- Update flutter dependencies in version.json for 3.24.3 (#247)
- Unify PR workflows into build.yml (#248)
- Rename build_and_push workflow to release (#249)
- Update flutter dependencies in version.json for 3.24.3 (#250)
- Update flutter version in flutter_version.json to 3.24.4 (#251)
- Update flutter dependencies in version.json for 3.24.4 (#252)
- Run renovate weekly to keep low noise with prHourlyLimit 2 (#255)
- Update flutter version in flutter_version.json to 3.24.5 (#262)
- Update flutter dependencies in version.json for 3.24.5 (#263)
- Update flutter version in flutter_version.json to 3.27.0 (#270)
- Update flutter dependencies in version.json for 3.27.0 (#271)
- Update flutter version in flutter_version.json to 3.27.1 (#272)
- Update flutter dependencies in version.json for 3.27.1 (#273)
- Update flutter version in flutter_version.json to 3.27.2 (#276)
- Update flutter dependencies in version.json for 3.27.2 (#277)
- Update flutter version in flutter_version.json to 3.27.3 (#279)
- Update flutter dependencies in version.json for 3.27.3 (#280)
- Update flutter version in flutter_version.json to 3.27.4 (#282)
- Update flutter dependencies in version.json for 3.27.4 (#283)
- Update flutter version in flutter_version.json to 3.29.0 (#286)
- Update flutter dependencies in version.json for 3.29.0 (#289)

<!-- generated by git-cliff -->

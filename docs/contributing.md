<!--- This markdown file was auto-generated from "contributing.mdx" -->

# Contributing

## Adding new Github Actions

When adding new Github Actions the `.github\renovate.json` needs to be checked and add the new action to:

* the automerge array if it's not an important action

### Dockerfile stages

1. `flutter` stage hast only the dependencies required to install flutter and common tools used by flutter internal commands, like `git`.
3. `android` stage has the dependencies required to install the Android SDK and to develop Flutter apps for Android.

// Source of truth for the per-backend CI usage examples under examples/.
// Generated to YAML by `cue export docs/examples.cue config/version.json -e <backend> --out yaml`
// (wired into `mise run docs`). config/version.json is unified in at eval time,
// so the image tag always tracks the pinned Flutter version.

// Provided by config/version.json (unified via the CLI).
flutter: version: string

_image: "ghcr.io/gmeligio/flutter-android:\(flutter.version)"

// GitHub Actions: the runner mounts Node for JavaScript actions, so the image
// needs nothing extra.
github: {
	name: "Build"
	on: push: {}
	jobs: build: {
		"runs-on": "ubuntu-22.04"
		container: image: _image
		steps: [
			{name: "Checkout", uses: "actions/checkout@v4"},
			{name: "Build", run: "flutter build apk"},
		]
	}
}

// GitLab CI clones the repo itself (no checkout action), so no Node is needed.
gitlab: build: {
	image:  _image
	script: ["flutter build apk"]
}

// act-based runners (Gitea/Forgejo) do NOT inject Node into a custom container
// image the way GitHub does, and this image stays minimal (no Node baked in).
// Install Node into the rootless user's home dir, then expose it on PATH.
_nodeVersion: "20.19.2"
_setupNode: {
	name: "Set up Node.js for actions/checkout (act-based runners don't provide it)"
	run:  """
		curl -fsSL https://nodejs.org/dist/v\(_nodeVersion)/node-v\(_nodeVersion)-linux-x64.tar.xz \\
		  | tar -xJ -C "$HOME"
		echo "$HOME/node-v\(_nodeVersion)-linux-x64/bin" >> "$GITHUB_PATH"
		"""
}

gitea: {
	name: "Build"
	on: push: {}
	jobs: build: {
		"runs-on": "ubuntu-22.04"
		container: image: _image
		steps: [
			_setupNode,
			{name: "Checkout", uses: "actions/checkout@v4"},
			{name: "Build", run: "flutter build apk"},
		]
	}
}

// Forgejo Actions uses the same schema and the same Node workaround.
forgejo: gitea

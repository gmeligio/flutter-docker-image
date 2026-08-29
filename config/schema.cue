import "strings"
import "list"

#PlatformVersion: {
	version!: int
}

#SemverMinor: {
	version!: =~ "^\\d+.\\d+$"
}

#SemverPatch: {
	version!: =~ "^\\d+.\\d+.\\d+$"
}

#SemverQuad: {
	version!: =~ "^\\d+\\.\\d+\\.\\d+\\.\\d+$"
}

#WindowsToolchain: {
	git: #SemverPatch
	vsBuildTools: {
		cmakeProject: #SemverQuad
		windows11Sdk: {
			build!: int
		}
		vcTools: #SemverQuad
	}
}

#FlutterVersion: {
	flutter: {
		channel!: "stable"
		commit!:  strings.MaxRunes(40)
		#SemverPatch
	}
}

#SemverVersion: #SemverMinor | #SemverPatch

// One published image. Conditional fields rather than a disjunction
// (#LinuxImage | #WindowsImage): CUE cannot pick a branch and reports every
// field of both as incomplete.
#Image: {
	name!:             string
	shortDescription!: strings.MaxRunes(100) // Docker Hub truncates beyond this
	scout!:            bool
	prTag!:            bool
	dockerfile!:       "android" | "windows"

	if dockerfile == "android" {
		target!:     string
		testConfig!: string
	}

	if dockerfile == "windows" {
		scout: false // Docker Scout does not support Windows images
		prTag: false // windows.yml builds with push: false, so no tag to clean up
	}
}

#Images: {
	images!: [...#Image] & list.MinItems(1) & list.UniqueItems
}

#Version: {
	#FlutterVersion

	android: {
		platforms!: [...#PlatformVersion] & list.MinItems(1) & list.UniqueItems
		java!: #PlatformVersion
		gradle!: #SemverVersion
		buildTools!: #SemverPatch
		cmdlineTools!: #SemverMinor
		ndk!: #SemverPatch
		cmake!: #SemverPatch
	}

	fastlane!: #SemverPatch

	windows!: #WindowsToolchain
}

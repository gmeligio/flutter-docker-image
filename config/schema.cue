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
		vcTools:       #SemverQuad
		nativeDesktop: #SemverQuad
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

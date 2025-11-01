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

#FlutterVersion: {
	flutter: {
		channel!: "stable"
		commit!:  strings.MaxRunes(40)
		#PatchVersion
	}
}

#SemverVersion: #SemverMinor | #SemverPatch

#Version: {
	#FlutterVersion

	android: {
		platforms!: [...#PlatformVersion] & list.MinItems(1) & list.UniqueItems
		gradle!: #SemverVersion
		buildTools!: #SemverPatch
		cmdlineTools!: #SemverMinor
		ndk!: #SemverPatch
		cmake!: #SemverPatch
	}

	fastlane!: #SemverPatch
}

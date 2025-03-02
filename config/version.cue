import "strings"
import "list"

#PlatformVersion: {
	version!: int
}

#MinorVersion: {
	version!: =~ "^\\d+.\\d+$"
}

#PatchVersion: {
	version!: =~ "^\\d+.\\d+.\\d+$"
}

#FlutterVersion: {
	flutter: {
		channel!: "stable" | "beta"
		commit!:  strings.MaxRunes(40)
		#PatchVersion
	}
}

#MinorOrPatchVersion: #MinorVersion | #PatchVersion

#Version: {
	#FlutterVersion

	android: {
		platforms!: [...#PlatformVersion] & list.MinItems(1) & list.UniqueItems
		gradle!: #MinorOrPatchVersion
		buildTools!: #PatchVersion
		cmdlineTools!: #MinorVersion
		ndk!: #PatchVersion
		cmake!: #PatchVersion
	}

	fastlane!: #PatchVersion
}

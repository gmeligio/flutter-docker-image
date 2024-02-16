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


#MinorOrPatchVersion: #MinorVersion | #PatchVersion

flutter: {
	channel!: "stable" | "beta"
	commit!:  strings.MaxRunes(40)
	#PatchVersion
}

android: {
	platforms!: [...#PlatformVersion] & list.MinItems(1) & list.UniqueItems
	gradle!: #MinorOrPatchVersion
	buildTools!: #PatchVersion
	cmdlineTools!: #MinorVersion
}

fastlane!: #PatchVersion

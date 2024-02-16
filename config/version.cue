import "strings"
import "list"

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
	platforms!: [ { version!: int } ] & list.MinItems(1)
	gradle!: #MinorOrPatchVersion
	buildTools!: #PatchVersion
	cmdlineTools!: #MinorVersion
}

fastlane!: #PatchVersion

import "strings"
import "list"

#Version2: {
	version!: =~ "^\\d+.\\d+$"
}

#Version3: {
	version!: =~ "^\\d+.\\d+.\\d+$"
}

flutter: {
	channel!: "stable" | "beta"
	commit!:  strings.MaxRunes(40)
	#Version3
}

android: {
	platforms!: [ { version!: int } ] & list.MinItems(1)
	gradle!: #Version2
	buildTools!: #Version3
	cmdlineTools!: #Version2
}

fastlane!: #Version3

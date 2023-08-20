import "strings"
import "list"

#Version3: {
	version!: =~ "^\\d+.\\d+.\\d+$"
}

flutter: {
	channel!: "stable" | "beta"
	commit!:  strings.MaxRunes(40)
	#Version3
}

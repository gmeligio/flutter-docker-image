package config

import "list"

#CommandTests: {
	name: _
	command: _
	args: _
	expectedOutput: [string]
}

#FileContentTests: {
	name: string
	path: _
	expectedContents: [string]
}

#ContainerStructureTest: {
	schemaVersion: _
	commandTests: [...#CommandTests]
	fileContentTests: [...#FileContentTests]
}

input: #ContainerStructureTest

android_cmdline_tools_test_expected_content: string @tag(android_cmdline_tools_test_expected_content)
android_cmdline_tools_version: string @tag(android_cmdline_tools_version)
android_ndk_version: string @tag(android_ndk_version)

output: {
	schemaVersion: input.schemaVersion
	
	commandTests: list.Concat([
		list.Take(input.commandTests, 2),
		[{
			input.commandTests[2]
			android_ndk_version: android_ndk_version
		}],
		list.Drop(input.commandTests, 3),
	])
	
	fileContentTests: list.Concat([
		if len(input.fileContentTests) > 0 {
			[{
				name: "Android SDK Command-line Tools is version \(android_cmdline_tools_version)"
				path: input.fileContentTests[0].path
				expectedContents: [android_cmdline_tools_test_expected_content]
			}],
		},
		list.Drop(input.fileContentTests, 1),
	])
}

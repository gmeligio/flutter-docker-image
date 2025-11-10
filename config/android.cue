package config

import "list"

#CommandTests: {
	name: _
	setup?: _
	teardown?: _
	command: _
	args: _
	expectedOutput?: [string]
	excludedOutput?: _
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
android_sdk_build_tools_version: string @tag(android_sdk_build_tools_version)

output: {
	schemaVersion: input.schemaVersion
	
	commandTests: list.Concat([
		list.Take(input.commandTests, 1),
		if len(input.fileContentTests) >= 3 {
			[
				{
					name: input.commandTests[1].name
					command: input.commandTests[1].command
					args: input.commandTests[1].args
					expectedOutput: [android_sdk_build_tools_version]
				},
				{
					name: input.commandTests[2].name
					command: input.commandTests[2].command
					args: input.commandTests[2].args
					expectedOutput: [android_ndk_version]
				}
			]
		},
		list.Drop(input.commandTests, 3),
	])
	
	fileContentTests: list.Concat([
		if len(input.fileContentTests) >= 1 {
			[{
				name: "Android SDK Command-line Tools is version \(android_cmdline_tools_version)"
				path: input.fileContentTests[0].path
				expectedContents: [android_cmdline_tools_test_expected_content]
			}],
		},
		list.Drop(input.fileContentTests, 1),
	])
}

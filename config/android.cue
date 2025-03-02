#FileContentTests: {
	name: string
	path: _
	expectedContents: [string]
}

#ContainerStructureTest: {
	schemaVersion: _
	commandTests: _
	fileContentTests: [...#FileContentTests]
}

input: #ContainerStructureTest

android_cmdline_tools_version: string @tag(android_cmdline_tools_version)
android_cmdline_tools_test_expected_content: string @tag(android_cmdline_tools_test_expected_content)

output: {
	schemaVersion: input.schemaVersion
	commandTests: input.commandTests
	fileContentTests: [
		{
			name: "Android SDK Command-line Tools is version \(android_cmdline_tools_version)"
			path: input.fileContentTests[0].path
			expectedContents: [android_cmdline_tools_test_expected_content]
		},
		input.fileContentTests[1]
	]
}

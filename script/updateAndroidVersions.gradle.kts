// Snippet to include at the end of android/app/build.gradle.kts
tasks.register<DefaultTask>("updateAndroidVersions") {
    doLast {
        val jsonFile = File("../../config/version.json")        
        
        // Parse existing JSON file
        val resultJsonMap = groovy.json.JsonSlurper().parseText(jsonFile.readText()) as MutableMap<String, Any>

        // Get unique platform versions
        val platformVersions = listOf(
            flutter.targetSdkVersion,
            flutter.compileSdkVersion
        ).distinct()

        // Create new Android version data
        val newJsonMap = mapOf(
            "platforms" to platformVersions.map {
                mapOf("version" to it)
            },
            "gradle" to mapOf("version" to gradle.gradleVersion)
        )

        // Merge new values into the existing JSON structure
        (resultJsonMap["android"] as? MutableMap<String, Any>)?.putAll(newJsonMap)

        // Format JSON with pretty printing
        val jsonStr = groovy.json.JsonOutput.toJson(resultJsonMap)
        val prettyStr = groovy.json.JsonOutput.prettyPrint(jsonStr)
        
        println(prettyStr)

        // Write updated JSON back to the file
        jsonFile.writeText("$prettyStr\n")
    }
}

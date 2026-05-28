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

        // Read the build-tools version that AGP will request at build time
        // (AGP's bundled default unless the Flutter template overrides it). This
        // is the only value that's guaranteed to match what sdkmanager installs
        // for `flutter create test_app && ./gradlew bundleRelease`.
        // Flutter 3.44 still sets android.newDsl=false (AppExtension); future
        // versions will flip to the new DSL (ApplicationExtension). Try both.
        val buildToolsVersion: String = project.extensions
            .findByType(com.android.build.api.dsl.ApplicationExtension::class.java)
            ?.buildToolsVersion
            ?: project.extensions
                .findByType(com.android.build.gradle.AppExtension::class.java)
                ?.buildToolsVersion
            ?: error("Could not resolve buildToolsVersion from the AGP extension on project ${project.path}")

        // Create new Android version data
        val newJsonMap = mapOf(
            "platforms" to platformVersions.map {
                mapOf("version" to it)
            },
            "gradle" to mapOf("version" to gradle.gradleVersion),
            "buildTools" to mapOf("version" to buildToolsVersion),
            "ndk" to mapOf("version" to flutter.ndkVersion)
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

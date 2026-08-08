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

        // Read Flutter's enforced Java floor from the plugin compiled at the
        // pinned tag. The app's settings.gradle.kts does
        // `includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")`, so
        // DependencyVersionChecker is on this task's classpath as a composite
        // included build. errorJavaVersion is `internal`, which is a Kotlin
        // module concept, not a JVM one: it compiles to a public getter mangled
        // as `getErrorJavaVersion$<module>`. Match by prefix rather than
        // hardcoding the suffix, so an upstream module rename doesn't break us.
        //
        // The property is also `@VisibleForTesting`, and Kotlin emits a second
        // method to hold that annotation: `getErrorJavaVersion$<module>$annotations`,
        // a static returning void. It is zero-arg and shares the prefix, so a
        // name match alone can select it -- `Class.methods` order is unspecified,
        // and it does differ between JDKs. Filtering on the JavaVersion return
        // type is what separates the real getter from the annotation holder.
        val checker = Class.forName("com.flutter.gradle.DependencyVersionChecker")
        val checkerInstance = checker.getField("INSTANCE").get(null)
        val errorJavaVersionGetter = checker.methods
            .filter { it.parameterCount == 0 }
            .filter { JavaVersion::class.java == it.returnType }
            .firstOrNull {
                it.name == "getErrorJavaVersion" || it.name.startsWith("getErrorJavaVersion$")
            }
            ?: error(
                "Could not find errorJavaVersion getter on DependencyVersionChecker. " +
                    "Flutter may have renamed or removed it. " +
                    "Available: ${checker.methods.map { it.name }.sorted()}"
            )

        // majorVersion, not toString(): the two diverge for Java 8 ("8" vs "1.8").
        val javaVersion = errorJavaVersionGetter.invoke(checkerInstance) as JavaVersion
        val javaMajor = javaVersion.majorVersion.toInt()

        println(
            "Derived Java major from errorJavaVersion " +
                "(${errorJavaVersionGetter.name}): $javaMajor"
        )

        // Assert the running JDK meets the floor before writing anything. This
        // fires on the cycle where Flutter raises its floor above the JDK the
        // previously published image installed -- turning a confusing failure
        // deep inside Flutter's own checkJavaVersion into a named one here.
        val currentJavaMajor = JavaVersion.current().majorVersion.toInt()
        check(currentJavaMajor >= javaMajor) {
            "Flutter requires Java $javaMajor or higher, but this JDK is $currentJavaMajor. " +
                "Rebuild the image with a JDK of at least $javaMajor."
        }

        // Create new Android version data
        val newJsonMap = mapOf(
            "platforms" to platformVersions.map {
                mapOf("version" to it)
            },
            "java" to mapOf("version" to javaMajor),
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

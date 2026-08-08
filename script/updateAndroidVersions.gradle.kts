// Snippet to include at the end of android/app/build.gradle.kts

// `internal` is a Kotlin module concept, not a JVM one, so the constant is
// reachable without setAccessible -- but the getter carries a `$<module>`
// suffix, and @VisibleForTesting emits a same-prefix `$annotations` twin that
// returns void. Match on the return type; `Class.methods` order is unspecified.
fun readFlutterMinimumJavaVersion(): JavaVersion {
    val checker = Class.forName("com.flutter.gradle.DependencyVersionChecker")
    val getter = checker.methods
        .filter { it.parameterCount == 0 && it.returnType == JavaVersion::class.java }
        .firstOrNull {
            it.name == "getErrorJavaVersion" || it.name.startsWith("getErrorJavaVersion$")
        }
        ?: error(
            "Could not find errorJavaVersion getter on DependencyVersionChecker. " +
                "Flutter may have renamed or removed it. " +
                "Available: ${checker.methods.map { it.name }.sorted()}"
        )

    return getter.invoke(checker.getField("INSTANCE").get(null)) as JavaVersion
}

tasks.register<DefaultTask>("updateAndroidVersions") {
    doLast {
        val jsonFile = File("../../config/version.json")

        val resultJsonMap = groovy.json.JsonSlurper().parseText(jsonFile.readText()) as MutableMap<String, Any>

        val platformVersions = listOf(
            flutter.targetSdkVersion,
            flutter.compileSdkVersion
        ).distinct()

        // The value AGP requests at build time is the only one guaranteed to match
        // what sdkmanager installs. Flutter 3.44 still sets android.newDsl=false;
        // later versions flip to ApplicationExtension, so try both.
        val buildToolsVersion: String = project.extensions
            .findByType(com.android.build.api.dsl.ApplicationExtension::class.java)
            ?.buildToolsVersion
            ?: project.extensions
                .findByType(com.android.build.gradle.AppExtension::class.java)
                ?.buildToolsVersion
            ?: error("Could not resolve buildToolsVersion from the AGP extension on project ${project.path}")

        val requiredJavaVersion = readFlutterMinimumJavaVersion()
        val javaMajor = requiredJavaVersion.majorVersion.toInt()

        val installedJavaVersion = JavaVersion.current()
        check(installedJavaVersion >= requiredJavaVersion) {
            "Flutter requires Java $javaMajor or higher, but this JDK is " +
                "${installedJavaVersion.majorVersion}. " +
                "Rebuild the image with a JDK of at least $javaMajor."
        }

        val newJsonMap = mapOf(
            "platforms" to platformVersions.map {
                mapOf("version" to it)
            },
            "java" to mapOf("version" to javaMajor),
            "gradle" to mapOf("version" to gradle.gradleVersion),
            "buildTools" to mapOf("version" to buildToolsVersion),
            "ndk" to mapOf("version" to flutter.ndkVersion)
        )

        (resultJsonMap["android"] as? MutableMap<String, Any>)?.putAll(newJsonMap)

        val jsonStr = groovy.json.JsonOutput.toJson(resultJsonMap)
        val prettyStr = groovy.json.JsonOutput.prettyPrint(jsonStr)

        println(prettyStr)

        jsonFile.writeText("$prettyStr\n")
    }
}

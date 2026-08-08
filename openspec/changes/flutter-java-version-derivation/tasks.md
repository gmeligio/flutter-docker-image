Ordered by the migration plan in `design.md`: each group is independently
revertable, and only group 4 can change the published image.

## 1. Self-wiring build arguments (design D3)

- [ ] 1.1 Capture the current `--build-arg` set as a baseline from a recent CI run's `docker buildx build` command line, to diff against after the refactor
- [ ] 1.2 Rewrite `script/setEnvironmentVariables.js` to walk `config/version.json` and derive ARG names from JSON paths (drop trailing `.version`/`.build`, lowercase, underscore-separate)
- [ ] 1.3 Add the explicit transformation table for non-scalar shapes (`android.platforms` → space-joined `android_platform_versions`) and the nested Windows names (`vs_cmake_version`, `vs_win11sdk_build`, `vs_vctools_version`)
- [ ] 1.4 Emit `BUILD_ARGS` as newline-separated `name=value` pairs via `core.exportVariable`, keeping the existing per-name exports that other steps still read (`FLUTTER_VERSION`, `IMAGE_REPOSITORY_PATH`)
- [ ] 1.5 Replace the build-args block with `build-args: ${{ env.BUILD_ARGS }}` in `build.yml` push path (~:158-164), `build.yml` fork path (~:180-186), `ci.yml` (~:84-90), `release.yml` (~:112-118)
- [ ] 1.6 Verify the emitted `--build-arg` set is byte-identical to the 1.1 baseline — same six args, same values, no behaviour change

## 2. Derive Java from Flutter's floor (design D1, D2)

- [ ] 2.1 In `script/updateAndroidVersions.gradle.kts`, resolve `com.flutter.gradle.DependencyVersionChecker` via `Class.forName` and get its `INSTANCE` field (Kotlin `object` singleton)
- [ ] 2.2 Find the zero-arg getter whose name is `getErrorJavaVersion` or starts with `getErrorJavaVersion$` (prefix match — do NOT hardcode the `$gradle` module suffix); `error(...)` with the sorted member list if absent
- [ ] 2.3 Invoke it, cast to `org.gradle.api.JavaVersion`, and take `.majorVersion.toInt()` — not `toString()`, which returns `"1.8"` for Java 8
- [ ] 2.4 Add `"java" to mapOf("version" to javaMajor)` to the task's `newJsonMap`, alongside the existing `platforms`/`gradle`/`buildTools`/`ndk` entries
- [ ] 2.5 Print the derived value, its provenance, and the resolved getter name (`Derived Java major from errorJavaVersion (getErrorJavaVersion$gradle): 17`)
- [ ] 2.6 Delete the `Derive installed Java major version` step in `update-version.yml` (~:296-303) and `script/java_version.sh`
- [ ] 2.7 Confirm the derivation yields `17` and produces **no diff** in `config/version.json` — the empty diff is the validation that old and new sources agree
- [ ] 2.8 Confirm the same task still runs in `build.yml:497-498`, which appends the script identically — the added Java write must not break that leg

## 3. Floor assertion (design D5)

- [ ] 3.1 Add `check(JavaVersion.current().majorVersion.toInt() >= javaMajor)` to `script/updateAndroidVersions.gradle.kts`, reusing the value derived in group 2 rather than a literal, with a failure message naming the required minimum
- [ ] 3.2 Place the assertion after the derivation but before any manifest write, so a below-floor JDK fails before mutating `config/version.json`

## 4. Dockerfile follows the manifest (design D4)

- [ ] 4.1 Move `ARG android_java_version` above the `ENV` block at `android.Dockerfile:139-140` (it currently sits at ~:176, after it)
- [ ] 4.2 Change `JAVA_HOME` to `"/usr/lib/jvm/java-${android_java_version}-openjdk-amd64"`
- [ ] 4.3 Change the apt install to `"openjdk-${android_java_version}-jdk-headless=$OPENJDK_17_JDK_HEADLESS_VERSION"`, leaving the `# renovate:` annotation and the `ARG OPENJDK_17_JDK_HEADLESS_VERSION` declaration untouched
- [ ] 4.4 Remove the three `moby/moby#29110` TODO comments at `:136-138` — the value now arrives from CI, so runtime discovery is no longer needed
- [ ] 4.5 Add `android_java_version` to the manifest-derived build args (should require no workflow edit if group 1 landed correctly — that is the test of 1.2)

## 5. Verification

- [ ] 5.1 `cue vet config/schema.cue -d '#Version' config/version.json` exits 0
- [ ] 5.2 `script/update_test.sh` regenerates `test/android.yml` with no diff (fixed point)
- [ ] 5.3 Build the android image locally and confirm `docker inspect` shows `JAVA_HOME` resolving to the OpenJDK 17 path, and no apt-pin `*_VERSION` in `Env`
- [ ] 5.4 `container-structure-test` passes `test/android.yml`, including the "Java is pinned" assertion
- [ ] 5.5 Confirm Renovate's regex still matches the openjdk ARG — run `renovate-config-validator --strict` and check the annotation/ARG pair is unchanged
- [ ] 5.6 Grep `android.Dockerfile` for literal `17` — it should appear only in the Renovate-managed patch pin default

## 6. Wrap-up

- [ ] 6.1 Open the PR with a Conventional Commit title, one logical concern
- [ ] 6.2 Note in the PR that `config/version.json` is intentionally unchanged, and why (both sources yield 17)
- [ ] 6.3 Open a GitHub issue for the deferred cleanup recorded in research F10: nine dead scripts, the `cmdlineTools` mirror, the dead `30.0.3` job-env lines
- [ ] 6.4 Answer the open question in `design.md` — whether `readme.md` should publish the Java version — or carry it forward as an issue

import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release signing material ──────────────────────────────────────────────────
//
// `android/key.properties` is gitignored; `android/key.properties.example`
// documents its four keys. Read at configure time so the warning below fires on
// every Gradle invocation, not only on an assembleRelease.
val keystorePropertiesFile: File = rootProject.file("key.properties")
val hasReleaseKeystore: Boolean = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use(keystoreProperties::load)
} else {
    // ⚠️ Loud, unconditional, and deliberately not an error.
    //
    // Failing the build would make `flutter run --release` impossible on a
    // machine that has never seen the keystore, and that is the machine CI and
    // every new contributor use. But an AAB signed with the debug key is
    // rejected by Play *at upload*, after a 200 MB upload and a 40-minute
    // build, with a message that does not say "you forgot key.properties".
    // This line is the only warning anybody gets.
    logger.warn(
        "⚠️  android/key.properties is missing — the release build will be signed " +
            "with the DEBUG key and Play Console will reject the bundle. " +
            "Copy android/key.properties.example and fill it in before shipping.",
    )
}

android {
    namespace = "uz.digitalgroup.tasuke"

    // ⚠️ Every one of these is `flutter.*` and never a literal.
    //
    // Play enforces a target-API floor that moves every August. When the floor
    // moves, the fix is `flutter upgrade` — the Flutter SDK carries the new
    // targetSdk and this file inherits it. Pinning a literal here is how an app
    // silently stops being updatable on Play a year later, and the symptom
    // ("your APK targets API N, which is below the requirement") appears at
    // upload time rather than in any build.
    // ⚠️ A literal, and the one place this project departs from `flutter.*`.
    //
    // `permission_handler_android` declares in its AAR metadata that consumers
    // must compile against API 37, and Flutter 3.47.5 still defaults
    // `flutter.compileSdkVersion` to 36 — so the build fails at the manifest
    // merger with a message about AAR metadata rather than about the plugin.
    // Raising compileSdk only changes which APIs may be *referenced*; targetSdk
    // below still comes from `flutter.*` and is what opts the app into new
    // runtime behaviour.
    //
    // Drop this back to `flutter.compileSdkVersion` the moment that default
    // reaches 37.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17

        // ⚠️ Half of a two-part requirement. The other half is the
        // `coreLibraryDesugaring` dependency at the bottom of this file, and
        // BOTH are needed.
        //
        // `flutter_local_notifications` compiles against java.time on a minSdk
        // far below 26. With this flag but without the dependency the project
        // still *compiles* — desugaring just finds no library to rewrite calls
        // against — and then every scheduled reminder dies at runtime with
        // NoClassDefFoundError: java.time.ZonedDateTime. Nothing on a Linux CI
        // box and no unit test can see that; only a phone can.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "uz.digitalgroup.tasuke"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // `rootProject.file()` leaves an absolute path alone and
                // resolves a relative one against `android/`, so key.properties
                // can point at a keystore kept outside the checkout.
                storeFile = keystoreProperties.getProperty("storeFile")?.let(rootProject::file)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    // ⚠️ AGP refuses any buildType `ndk.abiFilters` while `splits { abi }` is
    // active, and `flutter build apk --split-per-abi` turns that on by passing
    // `-Psplit-per-abi`. The error names the conflict but not the cause, and it
    // fires during configuration, so it looks like a broken build file rather
    // than a flag interaction.
    val splittingPerAbi = project.hasProperty("split-per-abi")

    buildTypes {
        getByName("debug") {
            ndk {
                // ⚠️ x86_64 must stay in the debug and profile ABI sets.
                //
                // The only emulator image on the build machine is x86_64.
                // Trimming this list to the two ARM ABIs — the obvious move
                // when someone is shrinking the release artifact — makes
                // `flutter run` fail on the emulator with
                // INSTALL_FAILED_NO_MATCHING_ABIS, which reads like a broken
                // AVD rather than a build-config change.
                if (!splittingPerAbi) {
                    abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
                }
            }
        }

        getByName("profile") {
            // Same reason as debug: the latency numbers in store/METRICS.md are
            // measured from a profile build, and that runs on the emulator too.
            ndk {
                if (!splittingPerAbi) {
                    abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
                }
            }
        }

        getByName("release") {
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    // The fallback the warning above is about. It keeps
                    // `flutter run --release` working; it does not produce a
                    // shippable bundle.
                    signingConfigs.getByName("debug")
                }

            isMinifyEnabled = true
            isShrinkResources = true

            // proguard-android-optimize.txt, not proguard-android.txt: the
            // optimizing variant is what the Flutter tooling assumes.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    androidResources {
        // ⚠️ The bundled whisper model (assets/models/*.bin, 57 MB) must be
        // STORED in the APK. Deflate saves 6% on quantised weights, and a
        // deflated asset makes AAsset_getBuffer inflate all of it into native
        // memory, in one go, on the UI thread, the first time
        // WhisperModelAsset copies it out. Stored, it is mapped straight from
        // the APK. Costs ~3.4 MB of installed size; Play compresses the
        // download anyway. tool/check_16k.sh fails a release APK where it is
        // not stored.
        noCompress(".bin")
    }

    packaging {
        jniLibs {
            // ⚠️ Uncompressed, page-aligned .so files in the APK.
            //
            // This is the default for our minSdk, but it is stated here because
            // `tool/check_16k.sh` depends on it: `zipalign -c -P 16` can only
            // verify 16 KB page alignment of libraries that are STORED, and a
            // future `useLegacyPackaging = true` (added to save a few MB) would
            // turn that check into a false pass on a build Play will reject on
            // Android 15 devices.
            useLegacyPackaging = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // ⚠️ The second half of `isCoreLibraryDesugaringEnabled` above. See the
    // comment there for what breaks when only one half is present.
    //
    // 2.1.4 is the floor flutter_local_notifications 22.x asks for.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}

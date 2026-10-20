plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Needed for Firebase
}

/**
 * Google Play's version code, worked out from the whole version rather than
 * from pubspec's build number alone.
 *
 * The two stores disagree about what a build number is, and the pubspec has
 * only one of them:
 *
 *   - Apple wants CFBundleVersion to increase only WITHIN one marketing
 *     version. Ship 4.7.4 build 3, bump the name to 4.7.5, and build 1 is
 *     accepted again. Starting each version at +1 is a normal iOS workflow.
 *   - Google wants versionCode to increase across the app's ENTIRE history,
 *     whatever the version name says. It has already seen 103, so a +1 is
 *     rejected with "Version code 1 has already been used" no matter what
 *     the name is.
 *
 * So pubspec keeps the number iOS wants, and Android folds the version name
 * into it:
 *
 *   4.7.5+1  ->  4 * 10_000_000 + 7 * 100_000 + 5 * 1_000 + 1  =  40_705_001
 *
 * which always rises, because every part of it does:
 *
 *   4.7.5+1  ->  40_705_001
 *   4.7.5+2  ->  40_705_002   (another build of the same version)
 *   4.7.6+1  ->  40_706_001   (a new patch, build number back to 1)
 *   4.8.0+1  ->  40_800_001
 *
 * Nothing to remember and nothing to keep in step by hand. The one thing
 * not to do is LOWER the version name, which would lower the code with it.
 */
val dlVersionCode: Int = run {
    val parts = flutter.versionName.split(".")
    fun part(i: Int) = parts.getOrNull(i)?.takeWhile(Char::isDigit)?.toIntOrNull() ?: 0

    val major = part(0)
    val minor = part(1)
    val patch = part(2)
    val build = flutter.versionCode

    // Each part has a column of its own, and overflowing one would quietly
    // carry into the next — which produces a LOWER code than the release
    // before it and a rejection from Play that says nothing about why. Fail
    // here instead, where the fix is obvious.
    require(minor < 100) { "pubspec version minor ($minor) must be under 100" }
    require(patch < 100) { "pubspec version patch ($patch) must be under 100" }
    require(build < 1000) { "pubspec build number ($build) must be under 1000" }

    // Play's ceiling is 2100000000, which this reaches at major 210.
    require(major < 210) { "pubspec version major ($major) must be under 210" }

    major * 10_000_000 + minor * 100_000 + patch * 1_000 + build
}

android {
    namespace = "com.app.carcalendar"
    compileSdk = flutter.compileSdkVersion
    // ndkVersion = flutter.ndkVersion
    ndkVersion = "27.0.12077973"  // ← Replace flutter.ndkVersion with this

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.app.carcalendar"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 28, not Flutter's default 24: Square's In-App Payments SDK requires
        // Android 9. Raising it drops API 24-27 (Android 7.0 - 8.1), which
        // can no longer install or update the app at all — a deliberate
        // trade for taking Square card payments in the app.
        minSdk = maxOf(flutter.minSdkVersion, 28)
        targetSdk = flutter.targetSdkVersion
        // Derived, not taken straight from pubspec. See dlVersionCode.
        versionCode = dlVersionCode
        versionName = flutter.versionName

          
        // Add this line 👇
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    packaging {
        resources {
            // Square's SDK pulls in a second okhttp, and both jars carry this
            // OSGi manifest. It is build metadata the app never reads, but two
            // copies at the same path fail mergeDebugJavaResource outright.
            excludes += "/META-INF/versions/9/OSGI-INF/MANIFEST.MF"
        }
    }
}

flutter {
    source = "../.."
}

// Add this section 👇
// dependencies {
//     coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
// }
dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // SQUARE — dropped with the native checkout. Restoring it means putting
    // this back alongside the sqip theme in styles.xml; the version must match
    // square_in_app_payments' MIN_IAP_SDK_VERSION.
    //
    // Named directly so its resources resolve at compile time: the plugin
    // pulls it in only as `implementation`, which keeps it off THIS module's
    // compile resource path, and styles.xml inherits from
    // sqip_Theme_BaseCardEntry to theme the card screen.
    // implementation("com.squareup.sdk.in-app-payments:card-entry:1.6.9")
    
    // Add these for crash fix:
    implementation("org.jetbrains.kotlin:kotlin-stdlib-jdk8:1.9.22")

    // Piwik PRO's Tracker reads the Google Advertising ID on construction and
    // only catches Exception, so a missing AdvertisingIdClient surfaces as an
    // uncaught NoClassDefFoundError. The SDK treats this dependency as optional
    // but the crash is not — it must be on the classpath.
    implementation("com.google.android.gms:play-services-ads-identifier:18.2.0")
    
    val composeBom = platform("androidx.compose:compose-bom:2024.02.00")
    implementation(composeBom)
    androidTestImplementation(composeBom)
    
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material:material")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.activity:activity-compose:1.8.2")
    
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.appcompat:appcompat:1.6.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
}
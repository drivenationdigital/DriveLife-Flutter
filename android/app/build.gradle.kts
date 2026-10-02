plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") // Needed for Firebase
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
        versionCode = flutter.versionCode
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

    // Square's card-entry AAR, named directly so its resources resolve at
    // compile time. The plugin already pulls it in, but as `implementation`,
    // which keeps it off THIS module's compile resource path — and
    // styles.xml inherits from sqip_Theme_BaseCardEntry to theme the card
    // screen, which then fails to link.
    //
    // Version must match square_in_app_payments' MIN_IAP_SDK_VERSION. Gradle
    // resolves to the higher of the two if they drift, so a mismatch is a
    // stale comment rather than a broken build — but keep them in step.
    implementation("com.squareup.sdk.in-app-payments:card-entry:1.6.9")
    
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
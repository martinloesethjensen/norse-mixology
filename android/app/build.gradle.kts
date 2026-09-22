plugins {
  alias(libs.plugins.android.application)
  alias(libs.plugins.compose.compiler)
  alias(libs.plugins.kotlin.serialization)
  alias(libs.plugins.ksp)
}

// The recipe/taxonomy catalog has one source of truth: /seed-data (also bundled by the iOS app).
// Copy just the two JSON files into the generated assets so the APK can never drift from it.
val seedDataDir = rootProject.file("../seed-data")
val seedAssetsDir = layout.buildDirectory.dir("generated/seed-assets")
val copySeedData = tasks.register<Copy>("copySeedData") {
    from(seedDataDir) { include("taxonomy.json", "recipes.json") }
    into(seedAssetsDir)
}
tasks.matching { it.name.startsWith("merge") && it.name.endsWith("Assets") }.configureEach { dependsOn(copySeedData) }

android {
    namespace = "dev.martinloeseth.norsemixology"
    compileSdk = 36
    defaultConfig {
        applicationId = "dev.martinloeseth.NorseMixology"
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
      compose = true
      aidl = false
      buildConfig = false
      shaders = false
    }

    sourceSets {
        getByName("main") { assets.directories.add(seedAssetsDir.get().asFile.absolutePath) }
    }

    testOptions {
        unitTests.all { it.systemProperty("seed.dir", seedDataDir.absolutePath) }
    }

    packaging {
      resources {
        excludes += "/META-INF/{AL2.0,LGPL2.1}"
      }
    }
}

kotlin {
    jvmToolchain(17)
}

dependencies {
  val composeBom = platform(libs.androidx.compose.bom)
  implementation(composeBom)
  androidTestImplementation(composeBom)

  // Core Android dependencies
  implementation(libs.androidx.core.ktx)
  implementation(libs.androidx.lifecycle.runtime.ktx)
  implementation(libs.androidx.activity.compose)

  // Arch Components
  implementation(libs.androidx.lifecycle.runtime.compose)
  implementation(libs.androidx.lifecycle.viewmodel.compose)

  // Compose
  implementation(libs.androidx.compose.ui)
  implementation(libs.androidx.compose.ui.tooling.preview)
  implementation(libs.androidx.compose.material3)
  // Tooling
  debugImplementation(libs.androidx.compose.ui.tooling)
  // Instrumented tests
  androidTestImplementation(libs.androidx.compose.ui.test.junit4)
  debugImplementation(libs.androidx.compose.ui.test.manifest)

  // Local tests: jUnit, coroutines, Android runner
  testImplementation(libs.junit)
  testImplementation(libs.kotlinx.coroutines.test)

  // Instrumented tests: jUnit rules and runners
  androidTestImplementation(libs.androidx.test.core)
  androidTestImplementation(libs.androidx.test.ext.junit)
  androidTestImplementation(libs.androidx.test.runner)
  androidTestImplementation(libs.androidx.test.espresso.core)

  // Navigation
  implementation(libs.androidx.navigation3.ui)
  implementation(libs.androidx.navigation3.runtime)
  implementation(libs.androidx.lifecycle.viewmodel.navigation3)

  // Local persistence
  implementation(libs.androidx.room3.runtime)
  implementation(libs.androidx.sqlite.framework)
  ksp(libs.androidx.room3.compiler)
  implementation(libs.androidx.datastore.preferences)
  implementation(libs.kotlinx.serialization.json)
  testImplementation(libs.androidx.sqlite.bundled.jvm)

  // Adaptive navigation chrome (bottom bar on phones, rail on tablets) + icons
  implementation(libs.androidx.compose.material3.adaptive.navigation.suite)
  implementation(libs.androidx.compose.material.icons.extended)
}

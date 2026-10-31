plugins { id("com.android.library"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.saycribe.relay"
    compileSdk = 34
    defaultConfig {
        minSdk = 26
        buildConfigField("String", "DEFAULT_RELAY_URL", "\"${project.findProperty("saycribe.relayUrl") ?: "https://saycribe-api.motomotos.com"}\"")
    }
    buildFeatures { buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}

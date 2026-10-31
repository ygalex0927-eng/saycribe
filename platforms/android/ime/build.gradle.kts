plugins { id("com.android.library"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.saycribe.ime"
    compileSdk = 34
    defaultConfig { minSdk = 26 }
    buildFeatures { aidl = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}

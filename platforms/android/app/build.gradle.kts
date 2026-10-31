plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
android {
    namespace = "com.saycribe.app"
    compileSdk = 34
    defaultConfig { applicationId = "com.saycribe.android"; minSdk = 26; targetSdk = 34; versionCode = 1; versionName = "0.1.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
}
dependencies { implementation(project(":asr-jni")); implementation(project(":relay")); implementation(project(":ime")) }

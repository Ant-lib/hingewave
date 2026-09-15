import java.util.Properties
import java.util.jar.Attributes
import java.util.jar.JarOutputStream
import java.util.jar.Manifest
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

val repoVersion = rootProject.file("../VERSION").readText().trim()

android {
    namespace = "com.antlib.hingewave"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.antlib.hingewave"
        minSdk = 33
        targetSdk = 35
        versionCode = repoVersion.split(".").fold(0) { acc, part -> acc * 100 + part.toInt() }
        versionName = repoVersion
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        create("release") {
            val props = rootProject.file("keystore.properties")
            if (props.exists()) {
                val p = Properties().apply { props.inputStream().use { load(it) } }
                storeFile = rootProject.file(p.getProperty("storeFile"))
                storePassword = p.getProperty("storePassword")
                keyAlias = p.getProperty("keyAlias")
                keyPassword = p.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            val release = signingConfigs.getByName("release")
            signingConfig = if (release.storeFile != null) release else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures {
        compose = true
    }
    testOptions {
        unitTests.isIncludeAndroidResources = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20240303")

    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:rules:1.6.1")
}

// Gradle hands the unit test worker its classpath through a Java argument file, where an
// apostrophe in a path acts as a quote and the test classes are never found. When the
// checkout path contains one, give the worker a pathing jar kept outside the project
// whose manifest points at the real entries instead.
tasks.withType<Test>().configureEach {
    if (!projectDir.path.contains("'")) return@configureEach
    doFirst {
        val entries = classpath.files
        val jar = File(System.getProperty("java.io.tmpdir"), "hingewave-test-classpath-$name.jar")
        val manifest = Manifest()
        manifest.mainAttributes[Attributes.Name.MANIFEST_VERSION] = "1.0"
        manifest.mainAttributes[Attributes.Name.CLASS_PATH] = entries.joinToString(" ") { it.toURI().toURL().toString() }
        JarOutputStream(jar.outputStream(), manifest).close()
        classpath = files(jar)
    }
}

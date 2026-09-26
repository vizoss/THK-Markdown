plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}

android {
    namespace = "com.thk.mdview"
    compileSdk = 34
    sourceSets.getByName("test").resources.srcDir("../../ios/Fixtures/data")
    sourceSets.getByName("test").resources.srcDir("../../examples/sse")

    defaultConfig {
        minSdk = 21
        targetSdk = 34
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }

    // Exposes the "release" AAR variant as a publishable Gradle component (AGP 7+ API).
    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")

    implementation("org.commonmark:commonmark:0.22.0")
    implementation("org.commonmark:commonmark-ext-gfm-tables:0.22.0")
    implementation("org.commonmark:commonmark-ext-gfm-strikethrough:0.22.0")
    implementation("org.commonmark:commonmark-ext-task-list-items:0.22.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.13")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("androidx.test.ext:junit:1.2.1")
    testImplementation("com.google.truth:truth:1.4.4")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.8.1")
}

// Stages a standard Maven repository; CI publishes it to the public maven-repo branch.
// CI validates VERSION_NAME against the release tag before publishing.
// Published version directories are immutable.
afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                groupId = "com.thk.mdview"
                artifactId = "thkmdview"
                version = (findProperty("VERSION_NAME") as String?) ?: "0.0.1-SNAPSHOT"
            }
        }
        repositories {
            maven {
                name = "StaticMaven"
                url = uri(findProperty("staticMavenDir") ?: layout.buildDirectory.dir("maven-repository").get().asFile)
            }
        }
    }
}

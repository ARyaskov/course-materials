pluginManagement {
    includeBuild("build-logic")
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

plugins {
    // Скачивает JDK нужной версии, если её нет локально (см. jvmToolchain в build-logic)
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

rootProject.name = "atrium"

include(
    "domain",
    "application",
    "infrastructure",
    "app-spring",
    "app-ktor",
    "benchmarks",
    "atrium-client",
    "detekt-rules",
)

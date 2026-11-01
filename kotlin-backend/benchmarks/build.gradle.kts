plugins {
    id("atrium.kotlin-conventions")
    alias(libs.plugins.kotlinx.benchmark)
    alias(libs.plugins.kotlin.allopen)
}

// Отдельный модуль: не входит в check, запускается вручную ./gradlew :benchmarks:benchmark (урок 14.6)
allOpen {
    annotation("org.openjdk.jmh.annotations.State")
}

sourceSets.create("jmh")

dependencies {
    "jmhImplementation"(project(":domain"))
    "jmhImplementation"(libs.kotlinx.benchmark)
}

benchmark {
    targets {
        register("jmh")
    }
    configurations {
        named("main") {
            warmups = 3
            iterations = 5
            iterationTime = 2
            iterationTimeUnit = "s"
        }
    }
}

plugins {
    id("atrium.kotlin-conventions")
    id("atrium.quality-conventions")
    alias(libs.plugins.binary.compatibility.validator)
}

// Библиотека для Java-команд (уроки 16.1, 16.5): явный API, JSpecify в байткоде, проверка бинарной совместимости
kotlin {
    explicitApi()
}

dependencies {
    api(libs.coroutines.core)
    api(libs.jspecify)
    implementation(libs.serialization.json)
    testImplementation(libs.bundles.testing)
    testImplementation(libs.junit.jupiter)
}

tasks.withType<JavaCompile>().configureEach {
    // Java-тест компилируется строго: raw types и unchecked из Kotlin-сигнатур — ошибка
    options.compilerArgs.addAll(listOf("-Xlint:all", "-Werror"))
}

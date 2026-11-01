plugins {
    id("atrium.kotlin-conventions")
}

// Собственные правила detekt — воплощение team guide (урок 16.3)
dependencies {
    compileOnly(libs.detekt.api)
    testImplementation(libs.detekt.test)
    testImplementation(libs.bundles.testing)
}

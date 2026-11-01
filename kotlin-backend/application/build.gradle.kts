plugins {
    id("atrium.kotlin-conventions")
    id("atrium.quality-conventions")
    `java-library`
    `java-test-fixtures`
}

dependencies {
    api(project(":domain"))
    api(libs.coroutines.core)
    implementation(libs.coroutines.slf4j)
    implementation(libs.kotlin.logging)

    testFixturesApi(testFixtures(project(":domain")))
    testFixturesApi(libs.jackson.databind)
    testFixturesImplementation(libs.jackson.module.kotlin)
    testImplementation(libs.coroutines.test)
    testImplementation(libs.kotest.property)
}

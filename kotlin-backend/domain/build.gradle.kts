plugins {
    id("atrium.kotlin-conventions")
    id("atrium.quality-conventions")
    `java-library`
    `java-test-fixtures`
}

// Домен не зависит ни от чего, кроме stdlib: проверяется отсутствием блока dependencies
// с чем-либо, кроме тестовых библиотек
dependencies {
    testFixturesApi(libs.kotest.property)
    testImplementation(libs.coroutines.test)
}

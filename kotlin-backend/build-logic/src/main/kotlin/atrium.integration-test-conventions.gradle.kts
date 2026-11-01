plugins {
    id("org.jetbrains.kotlin.jvm")
}

// Отдельный source set: интеграционные тесты (Docker) не запускаются с `test` и идут параллельно в CI
val integrationTest: SourceSet = sourceSets.create("integrationTest") {
    compileClasspath += sourceSets["main"].output + sourceSets["test"].output
    runtimeClasspath += sourceSets["main"].output + sourceSets["test"].output
}

configurations["integrationTestImplementation"].extendsFrom(configurations["testImplementation"])
configurations["integrationTestRuntimeOnly"].extendsFrom(configurations["testRuntimeOnly"])

val integrationTestTask = tasks.register<Test>("integrationTest") {
    description = "Тесты против Testcontainers (PostgreSQL, Kafka, Redis)"
    group = "verification"
    testClassesDirs = integrationTest.output.classesDirs
    classpath = integrationTest.runtimeClasspath
    useJUnitPlatform()
    shouldRunAfter(tasks.named("test"))
}

tasks.named("check") { dependsOn(integrationTestTask) }

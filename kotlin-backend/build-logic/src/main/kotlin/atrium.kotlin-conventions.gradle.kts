import org.jetbrains.kotlin.gradle.dsl.JvmDefaultMode
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion

plugins {
    id("org.jetbrains.kotlin.jvm")
    id("org.jetbrains.kotlin.plugin.power-assert")
}

// Один JDK для сборки всех модулей; foojay-resolver скачает его при отсутствии
kotlin {
    jvmToolchain(25)

    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_25)
        languageVersion.set(KotlinVersion.KOTLIN_2_4)
        apiVersion.set(KotlinVersion.KOTLIN_2_4)
        // Не генерировать DefaultImpls для интерфейсов, Java-вызывающие видят default-методы.
        jvmDefault.set(JvmDefaultMode.NO_COMPATIBILITY)
        // Предупреждения ловим в CI (-PwarningsAsErrors=true или CI=1), локально не мешаем разработчику (урок 15.4)
        allWarningsAsErrors.set(
            providers.gradleProperty("warningsAsErrors").map { it.toBoolean() }
                .orElse(providers.environmentVariable("CI").map { true })
                .orElse(false),
        )
        progressiveMode.set(true)
        freeCompilerArgs.addAll(
            // Nullability-аннотации Java-библиотек (JSR-305, JSpecify) — как ошибки, а не platform types
            "-Xjsr305=strict",
            "-Xjspecify-annotations=strict",
            // Проигнорированные результаты функций с @MustUseReturnValues — предупреждение
            "-Xreturn-value-checker=check",
        )
    }
}

// Диаграммы значений подвыражений в упавших утверждениях — только в тестовом коде
powerAssert {
    functions = listOf(
        "kotlin.assert",
        "kotlin.test.assertTrue",
        "kotlin.test.assertEquals",
        "kotlin.require",
        "kotlin.check",
    )
    includedSourceSets = listOf("test", "testFixtures")
}

java {
    withSourcesJar()
}

dependencies {
    val libs = versionCatalogs.named("libs")
    testImplementation(platform(libs.findLibrary("junit-bom").get()))
    testImplementation(libs.findLibrary("junit-jupiter").get())
    testImplementation(libs.findLibrary("kotest-assertions").get())
    testRuntimeOnly(libs.findLibrary("junit-platform-launcher").get())
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()
    // Тесты не должны зависеть от локали и часового пояса машины
    systemProperty("user.timezone", "UTC")
    jvmArgs("-Duser.language=en", "-Xshare:off")
    testLogging {
        events("failed", "skipped")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}

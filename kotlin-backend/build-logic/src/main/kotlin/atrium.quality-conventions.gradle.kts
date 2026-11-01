plugins {
    id("org.jlleitschuh.gradle.ktlint")
    id("io.gitlab.arturbosch.detekt")
    id("org.jetbrains.kotlinx.kover")
}

ktlint {
    // Версия самого ktlint (не плагина) — из каталога, чтобы правила совпадали с IDE и pre-commit
    version.set("1.8.0")
    android.set(false)
    ignoreFailures.set(false)
    filter {
        exclude { it.file.path.contains("/generated/") }
    }
}

dependencies {
    // Собственные правила team guide: RunBlockingInProduction, SwallowedCancellation, DataClassEntity (урок 16.3)
    if (project.name != "detekt-rules") {
        "detektPlugins"(project(":detekt-rules"))
    }
}

detekt {
    buildUponDefaultConfig = true
    allRules = false
    config.setFrom(rootProject.files("config/detekt/detekt.yml"))
    baseline = rootProject.file("config/detekt/detekt-baseline.xml")
    // Правила, требующие type resolution, включаются отдельной задачей detektMain в CI
}

tasks.withType<io.gitlab.arturbosch.detekt.Detekt>().configureEach {
    jvmTarget = "25"
    reports {
        html.required.set(true)
        sarif.required.set(true)
        txt.required.set(false)
    }
}

// Покрытие: порог только для модулей с логикой (domain, application); app-* покрыты интеграционными тестами (урок 15.4)
kover {
    reports {
        verify {
            if (project.name in setOf("domain", "application")) {
                rule { minBound(70) }
            }
        }
    }
}

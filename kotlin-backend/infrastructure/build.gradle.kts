import org.jooq.meta.jaxb.ForcedType

buildscript {
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath(libs.flyway.postgresql)
    }
}

plugins {
    id("atrium.kotlin-conventions")
    id("atrium.quality-conventions")
    `java-library`
    alias(libs.plugins.jooq.codegen)
    alias(libs.plugins.flyway)
}

// Сгенерированные jOOQ-классы коммитятся: сборка не зависит от базы, diff схемы виден в PR
sourceSets["main"].kotlin.srcDir("src/main/generated/kotlin")

flyway {
    url = project.findProperty("codegen.url") as String? ?: "jdbc:postgresql://localhost:55432/atrium"
    user = project.findProperty("codegen.user") as String? ?: "postgres"
    password = project.findProperty("codegen.password") as String? ?: "codegen"
    locations = arrayOf("filesystem:src/main/resources/db/migration")
}

jooq {
    version.set(libs.versions.jooq.asProvider())
    configurations {
        create("main") {
            generateSchemaSourceOnCompilation.set(false) // генерация — явный шаг scripts/jooq-codegen.sh
            jooqConfiguration.apply {
                jdbc.apply {
                    url = project.findProperty("codegen.url") as String? ?: "jdbc:postgresql://localhost:55432/atrium"
                    user = project.findProperty("codegen.user") as String? ?: "postgres"
                    password = project.findProperty("codegen.password") as String? ?: "codegen"
                }
                generator.apply {
                    name = "org.jooq.codegen.KotlinGenerator"
                    database.apply {
                        inputSchema = "public"
                        excludes = "flyway_schema_history"
                        isIncludeRoutines = false // Внутренние функции btree_gist не являются API приложения.
                        forcedTypes.add(
                            ForcedType().apply {
                                userType = "dev.atrium.domain.TimeSlot"
                                converter = "dev.atrium.infrastructure.jooq.TimeSlotConverter"
                                includeExpression = "public\\.bookings\\.slot"
                            },
                        )
                    }
                    generate.apply {
                        isGeneratedAnnotationDate = false
                        isKotlinNotNullRecordAttributes = true
                        isKotlinNotNullPojoAttributes = true
                    }
                    target.apply {
                        packageName = "dev.atrium.infrastructure.jooq.generated"
                        directory = "src/main/generated/kotlin"
                    }
                }
            }
        }
    }
}

// Генерация видит только актуальную схему и не запускается при ошибке миграций.
tasks.named("generateJooq") {
    dependsOn(tasks.named("flywayMigrate"))
}

dependencies {
    api(project(":application"))
    api(libs.jackson.databind)
    implementation(libs.jackson.module.kotlin)

    implementation(libs.hikari)
    implementation(libs.postgresql)
    implementation(libs.flyway.core)
    runtimeOnly(libs.flyway.postgresql)
    implementation(libs.exposed.core)
    implementation(libs.exposed.jdbc)
    implementation(libs.exposed.java.time)
    implementation(libs.jooq)
    implementation(libs.jooq.kotlin)
    jooqGenerator(libs.postgresql)
    implementation(libs.kafka.clients)
    implementation(libs.lettuce)
    implementation(libs.caffeine)
    implementation(libs.resilience4j.kotlin)
    implementation(libs.resilience4j.retry)
    implementation(libs.resilience4j.circuitbreaker)
    implementation(libs.resilience4j.timelimiter)
    implementation(libs.resilience4j.bulkhead)
    implementation(libs.resilience4j.micrometer)
    implementation(libs.micrometer.core)
    implementation(libs.opentelemetry.api)
    implementation(libs.opentelemetry.kotlin)
    implementation(libs.kotlin.logging)
    implementation(libs.coroutines.slf4j)
    implementation(libs.coroutines.jdk8)

    testImplementation(testFixtures(project(":application")))
    testImplementation(libs.testcontainers.junit)
    testImplementation(libs.testcontainers.postgresql)
    testImplementation(libs.testcontainers.kafka)
    testImplementation(libs.coroutines.test)
    testRuntimeOnly(libs.logback.classic)
}

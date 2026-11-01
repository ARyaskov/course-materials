plugins {
    id("atrium.kotlin-conventions")
    id("atrium.quality-conventions")
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ktor)
}

application {
    mainClass.set("dev.atrium.ktor.ApplicationKt")
}

dependencies {
    implementation(project(":infrastructure"))
    implementation(libs.hikari)
    implementation(libs.flyway.core)
    implementation(libs.kafka.clients)
    implementation(libs.resilience4j.circuitbreaker)

    implementation(libs.bundles.ktor.server)
    implementation(libs.ktor.server.rate.limit)
    implementation(libs.ktor.server.sse)
    implementation(libs.ktor.server.websockets)
    implementation(libs.ktor.server.auth)
    implementation(libs.ktor.server.auth.jwt)
    implementation(libs.ktor.server.metrics.micrometer)
    implementation(libs.ktor.server.openapi)
    implementation(libs.ktor.server.resources)
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.cio)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.serialization.json)
    implementation(libs.micrometer.prometheus)
    implementation(libs.opentelemetry.sdk)
    implementation(libs.opentelemetry.exporter.otlp)
    implementation(libs.opentelemetry.kotlin)
    implementation(libs.opentelemetry.ktor)
    implementation(libs.logback.classic)
    implementation(libs.logstash.encoder)
    implementation(libs.kotlin.logging)
    implementation(libs.coroutines.slf4j)

    testImplementation(testFixtures(project(":application")))
    testImplementation(libs.ktor.server.test.host)
    testImplementation(libs.ktor.client.mock)
    testImplementation(libs.testcontainers.junit)
    testImplementation(libs.testcontainers.postgresql)
    testImplementation(libs.coroutines.test)
}

ktor {
    fatJar {
        archiveFileName.set("atrium-ktor-all.jar")
    }
}

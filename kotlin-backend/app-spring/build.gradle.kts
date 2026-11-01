plugins {
    id("atrium.kotlin-conventions")
    id("atrium.quality-conventions")
    alias(libs.plugins.kotlin.spring)
    alias(libs.plugins.spring.boot)
}

dependencies {
    implementation(platform(libs.spring.boot.bom))
    implementation(project(":infrastructure"))
    implementation(libs.postgresql)
    implementation(libs.kotlin.logging)
    implementation(libs.resilience4j.circuitbreaker)

    implementation(libs.spring.boot.starter.webmvc)
    implementation(libs.spring.boot.starter.jackson)
    implementation(libs.jackson.module.kotlin)
    implementation(libs.spring.boot.starter.jdbc)
    implementation(libs.spring.boot.starter.data.jdbc)
    implementation(libs.spring.boot.starter.flyway)
    implementation(libs.spring.boot.starter.validation)
    implementation(libs.spring.boot.starter.actuator)
    implementation(libs.spring.boot.starter.opentelemetry)
    implementation(libs.spring.boot.starter.restclient)
    implementation(libs.spring.boot.starter.cache)
    implementation(libs.spring.boot.starter.security.oauth2.resource.server)
    implementation(libs.spring.kafka)
    implementation(libs.springdoc.openapi)
    implementation(libs.micrometer.prometheus)
    implementation(libs.coroutines.core)
    implementation(libs.coroutines.slf4j)
    implementation(libs.kotlin.reflect)
    runtimeOnly(libs.logstash.encoder)

    testImplementation(testFixtures(project(":application")))
    testImplementation(libs.spring.boot.starter.test)
    testImplementation(libs.spring.boot.starter.webmvc.test)
    testImplementation(libs.spring.boot.starter.jdbc.test)
    testImplementation(libs.spring.boot.testcontainers)
    testImplementation(libs.spring.boot.resttestclient)
    testImplementation(libs.spring.kafka.test)
    testImplementation(libs.spring.security.test)
    testImplementation(libs.springmockk)
    testImplementation(libs.testcontainers.junit)
    testImplementation(libs.testcontainers.postgresql)
    testImplementation(libs.testcontainers.kafka)
    testImplementation(libs.coroutines.test)
}

springBoot {
    buildInfo()
}

tasks.bootJar {
    archiveFileName.set("atrium-spring.jar")
}

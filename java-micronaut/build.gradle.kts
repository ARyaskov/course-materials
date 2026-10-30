plugins {
    id("io.micronaut.application") version "5.0.2"
    id("io.micronaut.test-resources") version "5.0.2"
    id("io.micronaut.aot") version "5.0.2"
    id("com.gradleup.shadow") version "9.4.1"
}

group = "io.meterway"
version = "1.0.0"

repositories {
    mavenCentral()
}

dependencies {
    annotationProcessor("io.micronaut:micronaut-http-validation")
    annotationProcessor("io.micronaut.data:micronaut-data-processor")
    annotationProcessor("io.micronaut.openapi:micronaut-openapi")
    annotationProcessor("io.micronaut.security:micronaut-security-processor")
    annotationProcessor("io.micronaut.serde:micronaut-serde-processor")
    annotationProcessor("io.micronaut.validation:micronaut-validation-processor")

    implementation("io.micronaut:micronaut-http-client")
    implementation("io.micronaut:micronaut-management")
    implementation("io.micronaut:micronaut-retry")
    implementation("io.micronaut:micronaut-websocket")
    implementation("io.micronaut.cache:micronaut-cache-caffeine")
    implementation("io.micronaut.data:micronaut-data-jdbc")
    implementation("io.micronaut.flyway:micronaut-flyway")
    implementation("io.micronaut.kafka:micronaut-kafka")
    implementation("io.micronaut.micrometer:micronaut-micrometer-annotation")
    implementation("io.micronaut.micrometer:micronaut-micrometer-core")
    implementation("io.micronaut.micrometer:micronaut-micrometer-registry-prometheus")
    implementation("io.micronaut.problem:micronaut-problem-json")
    implementation("io.micronaut.reactor:micronaut-reactor")
    implementation("io.micronaut.reactor:micronaut-reactor-http-client")
    implementation("io.micronaut.redis:micronaut-redis-lettuce")
    implementation("io.micronaut.security:micronaut-security-jwt")
    implementation("io.micronaut.serde:micronaut-serde-jackson")
    implementation("io.micronaut.sql:micronaut-jdbc-hikari")
    implementation("io.micronaut.tracing:micronaut-tracing-opentelemetry-http")
    implementation("io.micronaut.validation:micronaut-validation")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp")
    implementation("jakarta.persistence:jakarta.persistence-api")
    implementation("jakarta.validation:jakarta.validation-api")
    implementation("org.jspecify:jspecify")

    compileOnly("io.micronaut.openapi:micronaut-openapi-annotations")

    runtimeOnly("ch.qos.logback:logback-classic")
    runtimeOnly("org.flywaydb:flyway-database-postgresql")
    runtimeOnly("org.postgresql:postgresql")

    testImplementation("io.micronaut:micronaut-http-client")
    testImplementation("org.awaitility:awaitility:4.3.0")
    testImplementation("org.mockito:mockito-core")
    testImplementation("io.projectreactor:reactor-test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")

    developmentOnly("io.micronaut.controlpanel:micronaut-control-panel-management")
    developmentOnly("io.micronaut.controlpanel:micronaut-control-panel-ui")

    aotPlugins(platform("io.micronaut.platform:micronaut-platform:5.1.3"))
    aotPlugins("io.micronaut.security:micronaut-security-aot")
}

application {
    mainClass = "io.meterway.Application"
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(27)
    }
}

micronaut {
    runtime("netty")
    testRuntime("junit5")
    processing {
        incremental(true)
        annotations("io.meterway.*")
    }
    testResources {
        sharedServer = true
        version = "4.0.0"
    }
    aot {
        optimizeServiceLoading = false
        convertYamlToJava = false
        precomputeOperations = true
        cacheEnvironment = true
        optimizeClassLoading = true
        deduceEnvironment = true
        optimizeNetty = true
        replaceLogbackXml = true
        configurationProperties.put("micronaut.security.jwks.enabled", "false")
    }
}

graalvmNative.toolchainDetection = false
graalvmNative {
    binaries {
        all {
            buildArgs.add("-H:+SharedArenaSupport")
        }
    }
}

tasks.named<io.micronaut.gradle.docker.MicronautDockerfile>("dockerfile") {
    baseImage = "eclipse-temurin:27-jre"
}

tasks.withType<io.micronaut.gradle.testresources.StartTestResourcesService>().configureEach {
    useClassDataSharing = false
}

tasks.withType<AbstractTestTask>().configureEach {
    failOnNoDiscoveredTests = false
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.addAll(listOf("-parameters", "-Xlint:deprecation"))
}

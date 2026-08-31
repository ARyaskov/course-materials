plugins {
    java
    id("org.springframework.boot") version "4.0.6"
}

group = "com.example"
version = "0.0.1-SNAPSHOT"
description = "TaskFlow — учебный REST API (Java + Spring Boot 4) из курса Stepik"

repositories {
    mavenCentral()
}

val jjwtVersion = "0.12.6"
val springdocVersion = "3.0.3"

dependencies {
    // Управление версиями через Spring Boot BOM
    implementation(platform("org.springframework.boot:spring-boot-dependencies:4.0.6"))

    // Web / REST
    implementation("org.springframework.boot:spring-boot-starter-web")
    implementation("org.springframework.boot:spring-boot-starter-validation")

    // Данные
    implementation("org.springframework.boot:spring-boot-starter-data-jpa")
    // В Spring Boot 4 автоконфигурация Flyway вынесена в отдельный модуль:
    // без него flyway-core в classpath игнорируется и миграции не выполняются.
    implementation("org.springframework.boot:spring-boot-flyway")
    implementation("org.flywaydb:flyway-core")
    runtimeOnly("org.flywaydb:flyway-database-postgresql")
    runtimeOnly("org.postgresql:postgresql")

    // Безопасность
    implementation("org.springframework.boot:spring-boot-starter-security")
    implementation("io.jsonwebtoken:jjwt-api:$jjwtVersion")
    runtimeOnly("io.jsonwebtoken:jjwt-impl:$jjwtVersion")
    runtimeOnly("io.jsonwebtoken:jjwt-jackson:$jjwtVersion")

    // Внешние интеграции (retry). spring-retry не входит в Spring Boot BOM —
    // версия задаётся явно; spring-aspects подтягивает aspectjweaver для @EnableRetry.
    implementation("org.springframework.retry:spring-retry:2.0.12")
    implementation("org.springframework:spring-aspects")

    // Документация API
    implementation("org.springdoc:springdoc-openapi-starter-webmvc-ui:$springdocVersion")

    // Мониторинг
    implementation("org.springframework.boot:spring-boot-starter-actuator")

    // Тесты. Testcontainers не входит в Spring Boot BOM — версия задаётся явно
    // (стабильная ветка 1.x с привычными координатами junit-jupiter/postgresql).
    val testcontainersVersion = "1.21.4"
    testImplementation("org.springframework.boot:spring-boot-starter-test")
    testImplementation("org.springframework.security:spring-security-test")
    testImplementation("org.testcontainers:junit-jupiter:$testcontainersVersion")
    testImplementation("org.testcontainers:postgresql:$testcontainersVersion")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

java {
    toolchain {
        languageVersion = JavaLanguageVersion.of(26)
    }
}

tasks.withType<JavaCompile> {
    options.encoding = "UTF-8"
}

tasks.withType<Test> {
    useJUnitPlatform()
}

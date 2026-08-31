# --- Этап сборки ---
# JDK 26: проект собирается на Java 26 (toolchain в build.gradle.kts)
FROM eclipse-temurin:26-jdk AS build
WORKDIR /app
COPY gradle ./gradle
COPY gradlew settings.gradle.kts build.gradle.kts ./
RUN chmod +x gradlew && ./gradlew --no-daemon dependencies > /dev/null 2>&1 || true
COPY src ./src
RUN ./gradlew --no-daemon clean bootJar -x test

# --- Этап запуска ---
# JRE 26: bytecode major version 70 не запустится на более старой JRE
FROM eclipse-temurin:26-jre
WORKDIR /app
# wget нужен для HEALTHCHECK — в образе eclipse-temurin его нет
RUN apt-get update \
    && apt-get install -y --no-install-recommends wget \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -u 1001 appuser
COPY --from=build /app/build/libs/*.jar app.jar
USER appuser
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s \
    CMD wget -qO- http://localhost:8080/actuator/health || exit 1
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75.0", "-jar", "app.jar"]

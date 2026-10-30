import com.typesafe.sbt.packager.docker.DockerChmodType

lazy val root = (project in file("."))
  .enablePlugins(PlayJava)
  .settings(
    name := "beacon",
    organization := "io.beacon",
    version := "1.0.0",

    // Scala нужна только компилятору маршрутов и Twirl — прикладной код на Java 27.
    scalaVersion := "2.13.18",

    javacOptions ++= Seq(
      "-encoding", "UTF-8",
      "--release", "27",
      "-parameters",            // имена параметров: нужны Jackson и play.data
      "-Xlint:unchecked",
      "-Xlint:deprecation"
    ),

    libraryDependencies ++= Seq(
      guice,        // org.playframework:play-guice — DI на Guice 6 (javax.inject)
      javaJdbc,     // play-java-jdbc: play.db.Database, HikariCP
      evolutions,   // play-jdbc-evolutions: миграции схемы из conf/evolutions
      javaForms,    // play-java-forms: FormFactory, Bean Validation
      ws,           // play-ahc-ws: WSClient для исходящих вызовов
      caffeine,     // play-caffeine-cache: AsyncCacheApi
      filters,      // play-filters-helpers: CSRF, security headers, gzip, CORS, hosts
      "org.postgresql" % "postgresql" % "42.7.10",
      "com.h2database" % "h2"         % "2.4.240" % Test,
      "org.assertj"    % "assertj-core" % "3.27.7" % Test,
      "org.awaitility" % "awaitility"   % "4.3.0"  % Test
    ),

    // Импорты, доступные во всех Twirl-шаблонах без ручного @import.
    TwirlKeys.templateImports ++= Seq(
      "beacon.domain._",
      "views.html.helper.CSPNonce"
    ),

    // Маршруты разложены по conf/*.routes; доменные типы биндятся своими биндерами.
    play.sbt.routes.RoutesKeys.routesImport ++= Seq(
      "beacon.domain.ServiceKey",
      "beacon.domain.TimeRange"
    ),

    Test / testOptions += Tests.Argument(TestFrameworks.JUnit, "-a", "-v"),

    // Образ собирается через sbt-native-packager, который приходит с Play-плагином.
    Docker / packageName := "beacon",
    dockerBaseImage := "eclipse-temurin:27-jre",
    dockerExposedPorts := Seq(9000),
    dockerChmodType := DockerChmodType.UserGroupWriteExecute,
    dockerUpdateLatest := true
  )

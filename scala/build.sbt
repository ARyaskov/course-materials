ThisBuild / scalaVersion := "3.8.3"
ThisBuild / organization := "com.example"

lazy val root = project
  .in(file("."))
  .settings(
    name := "ledger-cli",
    version := "0.1.0",
    scalacOptions ++= Seq("-deprecation", "-feature", "-unchecked", "-Werror"),
    Compile / mainClass := Some("ledger.run"),
    libraryDependencies += "org.scalameta" %% "munit" % "1.3.1" % Test
  )

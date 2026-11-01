plugins {
    `kotlin-dsl`
}

// Precompiled script plugins из src/main/kotlin получают доступ к плагинам через classpath билд-логики
dependencies {
    implementation(plugin(libs.plugins.kotlin.jvm))
    implementation(plugin(libs.plugins.kotlin.power.assert))
    implementation(plugin(libs.plugins.ktlint))
    implementation(plugin(libs.plugins.detekt))
    implementation(plugin(libs.plugins.kover))
}

// Превращает координаты плагина из каталога в зависимость вида id:id.gradle.plugin:version
fun plugin(provider: Provider<PluginDependency>): Provider<String> =
    provider.map { "${it.pluginId}:${it.pluginId}.gradle.plugin:${it.version}" }

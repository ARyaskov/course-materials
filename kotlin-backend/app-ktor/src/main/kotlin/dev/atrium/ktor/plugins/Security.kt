package dev.atrium.ktor.plugins

import com.auth0.jwk.JwkProviderBuilder
import dev.atrium.domain.MemberId
import io.ktor.http.HttpStatusCode
import io.ktor.server.application.Application
import io.ktor.server.application.createRouteScopedPlugin
import io.ktor.server.application.install
import io.ktor.server.auth.Authentication
import io.ktor.server.auth.jwt.jwt
import io.ktor.server.auth.principal
import io.ktor.server.routing.Route
import java.net.URI
import java.util.concurrent.TimeUnit
import kotlin.uuid.Uuid

data class AuthConfig(val jwksUrl: String, val issuer: String)

/** Auth boundary app-ktor: JWT через JWKS, principal — MemberPrincipal; роли — собственный плагин withRole. */
fun Application.configureSecurity(config: AuthConfig) {
    val jwkProvider = JwkProviderBuilder(URI.create(config.jwksUrl).toURL())
        .cached(10, 24, TimeUnit.HOURS)
        .rateLimited(10, 1, TimeUnit.MINUTES)
        .build()

    install(Authentication) {
        jwt("member") {
            realm = "atrium"
            verifier(jwkProvider, config.issuer) { acceptLeeway(30) }
            validate { credential ->
                val subject = credential.payload.subject?.let(Uuid::parseOrNull) ?: return@validate null
                val roles = credential.payload.getClaim("roles").asList(String::class.java).orEmpty().toSet()
                MemberPrincipal(MemberId(subject), roles)
            }
            challenge { _, _ -> call.respondProblem(HttpStatusCode.Unauthorized, "unauthenticated", "Bearer token is missing or invalid") }
        }
    }
}

class RoleConfig {
    var role: String = "admin"
}

/** Ktor не имеет встроенной авторизации по ролям — плагин уровня маршрута. */
val RequireRole = createRouteScopedPlugin("RequireRole", ::RoleConfig) {
    val role = pluginConfig.role
    onCall { call ->
        val principal = call.principal<MemberPrincipal>() ?: call.attributes.getOrNull(MemberPrincipalKey)
        if (principal == null || role !in principal.roles) {
            call.respondProblem(HttpStatusCode.Forbidden, "forbidden", "Role '$role' is required")
        }
    }
}

fun Route.withRole(role: String, build: Route.() -> Unit): Route {
    install(RequireRole) { this.role = role }
    build()
    return this
}

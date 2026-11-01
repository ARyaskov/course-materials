package dev.atrium.ktor.plugins

import dev.atrium.domain.MemberId
import io.ktor.server.application.ApplicationCall
import io.ktor.server.application.createApplicationPlugin
import io.ktor.server.auth.principal
import io.ktor.server.request.header
import io.ktor.util.AttributeKey
import kotlin.uuid.Uuid

data class MemberPrincipal(val memberId: MemberId, val roles: Set<String> = emptySet())

val MemberPrincipalKey = AttributeKey<MemberPrincipal>("MemberPrincipal")

/** Только для local/test: участник из заголовка X-Member-Id. В production заменяется JWT (урок 10.7). */
val DevPrincipal = createApplicationPlugin("DevPrincipal") {
    onCall { call ->
        call.request.header("X-Member-Id")?.let(Uuid::parseOrNull)?.let { call.attributes.put(MemberPrincipalKey, MemberPrincipal(MemberId(it))) }
    }
}

/** Маршруты не знают, откуда пришёл участник: DevPrincipal в тестах, Authentication в production. */
fun ApplicationCall.memberPrincipal(): MemberPrincipal? = attributes.getOrNull(MemberPrincipalKey) ?: principal<MemberPrincipal>()

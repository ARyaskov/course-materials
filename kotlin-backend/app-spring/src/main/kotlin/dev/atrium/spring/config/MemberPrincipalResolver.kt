package dev.atrium.spring.config

import dev.atrium.domain.MemberId
import dev.atrium.spring.api.MemberPrincipal
import org.springframework.context.annotation.Configuration
import org.springframework.core.MethodParameter
import org.springframework.http.HttpStatus
import org.springframework.security.core.context.SecurityContextHolder
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken
import org.springframework.stereotype.Component
import org.springframework.web.bind.support.WebDataBinderFactory
import org.springframework.web.context.request.NativeWebRequest
import org.springframework.web.method.support.HandlerMethodArgumentResolver
import org.springframework.web.method.support.ModelAndViewContainer
import org.springframework.web.server.ResponseStatusException
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer
import kotlin.uuid.Uuid

/** Единственный класс app-spring, читающий SecurityContextHolder: выполняется до входа в suspend-контроллер. */
@Component
class MemberPrincipalResolver : HandlerMethodArgumentResolver {
    override fun supportsParameter(parameter: MethodParameter): Boolean = parameter.parameterType == MemberPrincipal::class.java

    override fun resolveArgument(
        parameter: MethodParameter,
        mavContainer: ModelAndViewContainer?,
        webRequest: NativeWebRequest,
        binderFactory: WebDataBinderFactory?,
    ): Any {
        val auth = SecurityContextHolder.getContext().authentication as? JwtAuthenticationToken
            ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED)
        val subject = auth.token.subject ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "sub is missing")
        val memberId = Uuid.parseOrNull(subject) ?: throw ResponseStatusException(HttpStatus.UNAUTHORIZED, "sub is not a UUID")
        val roles = auth.authorities.mapNotNull { it.authority?.removePrefix("ROLE_")?.lowercase() }.toSet()
        return MemberPrincipal(MemberId(memberId), roles)
    }
}

@Configuration
class WebConfig(private val resolver: MemberPrincipalResolver) : WebMvcConfigurer {
    override fun addArgumentResolvers(resolvers: MutableList<HandlerMethodArgumentResolver>) {
        resolvers += resolver
    }
}

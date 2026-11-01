package dev.atrium.spring.config

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.core.convert.converter.Converter
import org.springframework.http.HttpStatus
import org.springframework.http.MediaType
import org.springframework.http.ProblemDetail
import org.springframework.security.authentication.AbstractAuthenticationToken
import org.springframework.security.config.annotation.web.builders.HttpSecurity
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity
import org.springframework.security.config.annotation.web.invoke
import org.springframework.security.config.http.SessionCreationPolicy
import org.springframework.security.core.authority.SimpleGrantedAuthority
import org.springframework.security.oauth2.jwt.Jwt
import org.springframework.security.oauth2.core.OAuth2AuthenticationException
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationToken
import org.springframework.security.web.AuthenticationEntryPoint
import org.springframework.security.web.SecurityFilterChain
import tools.jackson.databind.json.JsonMapper
import java.net.URI

/** Auth boundary app-spring: JWT resource server, правила маршрутов в одном месте, Problem Details для 401. */
@Configuration
@EnableWebSecurity
class SecurityConfig(private val jsonMapper: JsonMapper) {

    @Bean
    fun securityFilterChain(http: HttpSecurity): SecurityFilterChain {
        http {
            csrf { disable() } // stateless API без cookie-сессий
            sessionManagement { sessionCreationPolicy = SessionCreationPolicy.STATELESS }
            authorizeHttpRequests {
                authorize("/actuator/health/**", permitAll)
                authorize("/api/v1/locations/**", permitAll)
                authorize("/api/v1/rooms/*/occupancy/stream", permitAll) // табло без токена
                authorize("/api/v1/admin/**", hasRole("ADMIN"))
                authorize("/api/v1/**", authenticated)
                authorize(anyRequest, denyAll)
            }
            oauth2ResourceServer { jwt { jwtAuthenticationConverter = memberJwtConverter() } }
            exceptionHandling { authenticationEntryPoint = problemDetailsEntryPoint() }
        }
        return http.build()
    }

    private fun memberJwtConverter(): Converter<Jwt, AbstractAuthenticationToken> = Converter { jwt ->
        val roles = (jwt.getClaimAsStringList("roles") ?: emptyList()).map { SimpleGrantedAuthority("ROLE_${it.uppercase()}") }
        val subject = jwt.subject ?: throw OAuth2AuthenticationException("invalid_token")
        JwtAuthenticationToken(jwt, roles, subject)
    }

    private fun problemDetailsEntryPoint() = AuthenticationEntryPoint { request, response, _ ->
        val problem = ProblemDetail.forStatusAndDetail(HttpStatus.UNAUTHORIZED, "Bearer token is missing or invalid").apply {
            type = URI.create("https://atrium.dev/problems/unauthenticated")
            title = "Unauthenticated"
            instance = URI.create(request.requestURI)
        }
        response.status = HttpStatus.UNAUTHORIZED.value()
        response.contentType = MediaType.APPLICATION_PROBLEM_JSON_VALUE
        response.writer.write(jsonMapper.writeValueAsString(problem))
    }
}

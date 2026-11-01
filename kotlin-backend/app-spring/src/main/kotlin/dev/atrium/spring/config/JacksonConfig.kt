package dev.atrium.spring.config

import org.springframework.boot.jackson.autoconfigure.JsonMapperBuilderCustomizer
import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import tools.jackson.databind.DeserializationFeature
import tools.jackson.databind.cfg.DateTimeFeature
import com.fasterxml.jackson.annotation.JsonInclude

@Configuration(proxyBeanMethods = false)
class JacksonConfig {
    @Bean
    fun atriumJsonCustomizer(): JsonMapperBuilderCustomizer = JsonMapperBuilderCustomizer { builder ->
        builder
            .disable(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES) // tolerant reader
            .enable(DeserializationFeature.FAIL_ON_NULL_FOR_PRIMITIVES) // null в Int — ошибка, а не 0
            .disable(DateTimeFeature.WRITE_DATES_AS_TIMESTAMPS) // Instant как ISO-8601
            .changeDefaultPropertyInclusion { it.withValueInclusion(JsonInclude.Include.NON_NULL) }
    }
}

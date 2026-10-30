package io.meterway.config;

import io.micronaut.context.annotation.Bean;
import io.micronaut.context.annotation.Factory;
import io.micronaut.context.annotation.Requires;
import jakarta.inject.Singleton;

import java.time.Clock;

/**
 * Бины, которые нельзя пометить аннотацией: класс чужой и процессор его не видел.
 * {@code Clock} внедряется везде вместо {@code Instant.now()} — иначе тест на границу
 * расчётного периода приходится писать через ожидание реального времени.
 */
@Factory
public class CoreFactory {

    @Singleton
    @Requires(missingBeans = Clock.class)
    Clock systemClock() {
        return Clock.systemUTC();
    }

    @Bean
    @Singleton
    java.security.SecureRandom secureRandom() {
        return new java.security.SecureRandom();
    }
}

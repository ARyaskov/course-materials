package com.example.taskflow.notification;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.boot.context.properties.bind.DefaultValue;

@ConfigurationProperties(prefix = "notifications")
public record NotificationProperties(
    @DefaultValue("http://localhost:9000") String baseUrl,
    @DefaultValue("3000") int connectTimeoutMs,
    @DefaultValue("5000") int readTimeoutMs,
    @DefaultValue("3") int maxAttempts
) {}

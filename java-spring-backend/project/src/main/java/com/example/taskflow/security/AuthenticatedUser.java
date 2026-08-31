package com.example.taskflow.security;

// Простой record для хранения данных аутентифицированного пользователя.
// Кладётся в SecurityContext как principal (см. JwtAuthenticationFilter).
public record AuthenticatedUser(Long userId, String email) {}

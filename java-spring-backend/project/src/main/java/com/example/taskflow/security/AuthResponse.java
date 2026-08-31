package com.example.taskflow.security;

public record AuthResponse(
    String token,
    Long userId,
    String email
) {}

package com.example.taskflow.user;

import java.time.Instant;

public record UserResponse(
    Long id,
    String username,
    String email,
    String displayName,
    Instant createdAt
) {
    public static UserResponse from(User user) {
        return new UserResponse(
            user.getId(),
            user.getUsername(),
            user.getEmail(),
            user.getDisplayName(),
            user.getCreatedAt()
        );
    }
}

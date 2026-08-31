package com.example.taskflow.project;

import java.time.Instant;

public record ProjectResponse(
    Long id,
    String name,
    String description,
    Long ownerId,
    String ownerUsername,
    Instant createdAt
) {
    public static ProjectResponse from(Project project) {
        return new ProjectResponse(
            project.getId(),
            project.getName(),
            project.getDescription(),
            project.getOwner().getId(),
            project.getOwner().getUsername(),
            project.getCreatedAt()
        );
    }
}

package com.example.taskflow.task;

import java.time.Instant;

public record TaskResponse(
    Long id,
    String title,
    String description,
    String status,
    String priority,
    Long projectId,
    String projectName,
    Long creatorId,
    String creatorUsername,
    Long assigneeId,
    String assigneeUsername,
    Instant dueDate,
    Instant createdAt,
    Instant updatedAt
) {
    public static TaskResponse from(Task task) {
        var assignee = task.getAssignee();
        return new TaskResponse(
            task.getId(),
            task.getTitle(),
            task.getDescription(),
            task.getStatus(),
            task.getPriority(),
            task.getProject().getId(),
            task.getProject().getName(),
            task.getCreator().getId(),
            task.getCreator().getUsername(),
            assignee != null ? assignee.getId() : null,
            assignee != null ? assignee.getUsername() : null,
            task.getDueDate(),
            task.getCreatedAt(),
            task.getUpdatedAt()
        );
    }
}

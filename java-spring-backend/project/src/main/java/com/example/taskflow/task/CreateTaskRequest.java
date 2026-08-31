package com.example.taskflow.task;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.Instant;

// Создание задачи
public record CreateTaskRequest(
    @NotBlank(message = "Title must not be blank")
    @Size(max = 255, message = "Title must not exceed 255 characters")
    String title,

    String description,

    @NotNull(message = "Project ID is required")
    Long projectId,

    Long assigneeId,
    Instant dueDate
) {}

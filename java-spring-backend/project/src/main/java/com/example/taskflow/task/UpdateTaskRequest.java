package com.example.taskflow.task;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import java.time.Instant;

// Полное обновление задачи
public record UpdateTaskRequest(
    @NotBlank @Size(max = 255)
    String title,

    String description,

    @NotBlank
    String status,

    @NotBlank
    String priority,

    Long assigneeId,
    Instant dueDate
) {}

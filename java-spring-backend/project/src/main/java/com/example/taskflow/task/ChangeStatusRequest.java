package com.example.taskflow.task;

import jakarta.validation.constraints.NotBlank;

// Только смена статуса
public record ChangeStatusRequest(
    @NotBlank(message = "Status must not be blank")
    String status
) {}

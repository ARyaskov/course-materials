package com.example.taskflow.notification;

public record NotificationRequest(
    Long userId,
    Long taskId,
    String type,    // TASK_CREATED, TASK_ASSIGNED, TASK_COMPLETED
    String taskTitle
) {}

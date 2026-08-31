package com.example.taskflow.notification;

public interface NotificationGateway {
    void notifyTaskCreated(Long userId, Long taskId, String taskTitle);
    void notifyTaskAssigned(Long assigneeId, Long taskId, String taskTitle);
}

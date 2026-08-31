package com.example.taskflow.task;

// Только назначение/снятие исполнителя (null = снять исполнителя)
public record AssignTaskRequest(
    Long assigneeId
) {}

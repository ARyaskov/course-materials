package com.example.taskflow.task;

/**
 * Приоритеты задачи в TaskFlow.
 * <p>
 * Как и {@link TaskStatus}, в сущности хранится строкой; enum фиксирует
 * допустимые значения.
 */
public enum Priority {
    LOW,
    MEDIUM,
    HIGH
}

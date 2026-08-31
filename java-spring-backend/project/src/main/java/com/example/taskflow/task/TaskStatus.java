package com.example.taskflow.task;

/**
 * Статусы задачи в TaskFlow.
 * <p>
 * В сущности {@link Task} статус хранится как строка (см. курс — раздел
 * «Service layer»), а этот enum фиксирует допустимый набор значений и
 * используется как справочник/контракт API.
 */
public enum TaskStatus {
    TODO,
    IN_PROGRESS,
    IN_REVIEW,
    DONE,
    CANCELLED
}

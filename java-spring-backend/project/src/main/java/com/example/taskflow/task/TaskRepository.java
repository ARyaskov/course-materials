package com.example.taskflow.task;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.Instant;
import java.util.List;

public interface TaskRepository extends JpaRepository<Task, Long> {

    // -------------------------------------------------------
    // Поиск по одному полю
    // -------------------------------------------------------

    // Задачи проекта (с пагинацией)
    Page<Task> findByProjectId(Long projectId, Pageable pageable);

    // Задачи проекта с определённым статусом
    List<Task> findByProjectIdAndStatus(Long projectId, String status);

    // Задачи конкретного исполнителя
    List<Task> findByAssigneeId(Long assigneeId);

    // Задачи по создателю
    List<Task> findByCreatorId(Long creatorId);

    // Задачи с конкретным статусом (глобально — для аналитики)
    List<Task> findByStatus(String status);

    // -------------------------------------------------------
    // Сортировка через имя метода
    // -------------------------------------------------------

    // Задачи проекта, отсортированные по дате создания (новые первыми)
    List<Task> findByProjectIdOrderByCreatedAtDesc(Long projectId);

    // Задачи исполнителя, отсортированные по дедлайну
    List<Task> findByAssigneeIdOrderByDueDateAsc(Long assigneeId);

    // -------------------------------------------------------
    // Проверка существования
    // -------------------------------------------------------

    boolean existsByProjectIdAndId(Long projectId, Long taskId);

    // -------------------------------------------------------
    // Подсчёт
    // -------------------------------------------------------

    long countByProjectId(Long projectId);

    long countByProjectIdAndStatus(Long projectId, String status);

    long countByAssigneeId(Long assigneeId);

    // -------------------------------------------------------
    // Запросы с дополнительными условиями
    // -------------------------------------------------------

    // Просроченные задачи (дедлайн в прошлом, статус не DONE и не CANCELLED)
    @Query("""
            SELECT t FROM Task t
            WHERE t.assignee.id = :userId
              AND t.dueDate < :now
              AND t.status NOT IN ('DONE', 'CANCELLED')
            ORDER BY t.dueDate ASC
            """)
    List<Task> findOverdueTasksForUser(@Param("userId") Long userId,
                                       @Param("now") Instant now);

    // Задачи проекта с загрузкой связей (без N+1)
    @Query("""
            SELECT t FROM Task t
            JOIN FETCH t.project
            JOIN FETCH t.creator
            LEFT JOIN FETCH t.assignee
            WHERE t.project.id = :projectId
            ORDER BY t.createdAt DESC
            """)
    List<Task> findByProjectIdWithDetails(@Param("projectId") Long projectId);

    // Поиск по подстроке в заголовке (без учёта регистра)
    @Query("""
            SELECT t FROM Task t
            WHERE t.project.id = :projectId
              AND LOWER(t.title) LIKE LOWER(CONCAT('%', :query, '%'))
            ORDER BY t.createdAt DESC
            """)
    List<Task> searchByTitleInProject(@Param("projectId") Long projectId,
                                      @Param("query") String query,
                                      Pageable pageable);
}

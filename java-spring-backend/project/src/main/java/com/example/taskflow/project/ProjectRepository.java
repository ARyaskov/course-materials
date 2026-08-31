package com.example.taskflow.project;

import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

public interface ProjectRepository extends JpaRepository<Project, Long> {

    // Проекты пользователя (с пагинацией)
    Page<Project> findByOwnerId(Long ownerId, Pageable pageable);

    // Проверка: является ли пользователь владельцем проекта
    boolean existsByIdAndOwnerId(Long projectId, Long ownerId);

    // Количество проектов пользователя
    long countByOwnerId(Long ownerId);
}

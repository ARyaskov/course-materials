package com.example.taskflow.project;

import jakarta.persistence.Embeddable;

// Составной первичный ключ для project_members
@Embeddable
public record ProjectMemberId(Long projectId, Long userId)
    implements java.io.Serializable {}

package com.example.taskflow.common.exception;

import org.springframework.http.HttpStatus;

public class ResourceNotFoundException extends AppException {

    public ResourceNotFoundException(String message) {
        super(HttpStatus.NOT_FOUND, message);
    }

    // Удобный фабричный метод
    public static ResourceNotFoundException ofTask(Long id) {
        return new ResourceNotFoundException("Task not found: " + id);
    }

    public static ResourceNotFoundException ofProject(Long id) {
        return new ResourceNotFoundException("Project not found: " + id);
    }

    public static ResourceNotFoundException ofUser(Long id) {
        return new ResourceNotFoundException("User not found: " + id);
    }
}

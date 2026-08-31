package com.example.taskflow.common.exception;

import org.springframework.http.HttpStatus;

// Нарушение бизнес-правила: данные корректны, операция невозможна
public class BusinessRuleException extends AppException {

    public BusinessRuleException(String message) {
        super(HttpStatus.UNPROCESSABLE_ENTITY, message);
    }
}

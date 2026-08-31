package com.example.taskflow.common.exception;

import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.validation.FieldError;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.context.request.WebRequest;

import java.net.URI;
import java.util.stream.Collectors;

@RestControllerAdvice
public class GlobalExceptionHandler {

    // Наши custom exceptions (ResourceNotFoundException, ConflictException и т.д.)
    @ExceptionHandler(AppException.class)
    public ProblemDetail handleAppException(AppException ex, WebRequest request) {
        var problem = ProblemDetail.forStatusAndDetail(
            ex.getStatus(), ex.getMessage());
        problem.setInstance(URI.create(extractPath(request)));
        return problem;
    }

    // Ошибки валидации @Valid — поля не прошли аннотации
    @ExceptionHandler(MethodArgumentNotValidException.class)
    public ProblemDetail handleValidation(MethodArgumentNotValidException ex,
                                          WebRequest request) {
        var detail = ex.getBindingResult().getFieldErrors().stream()
                .map(fe -> fe.getField() + ": " + fe.getDefaultMessage())
                .collect(Collectors.joining("; "));

        var problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.UNPROCESSABLE_ENTITY, detail);
        problem.setTitle("Validation failed");
        problem.setInstance(URI.create(extractPath(request)));
        return problem;
    }

    // Все остальные необработанные исключения -> 500
    @ExceptionHandler(Exception.class)
    public ProblemDetail handleGeneric(Exception ex, WebRequest request) {
        // Логируем полный стек для разработчиков
        // log.error("Unexpected error", ex);  <- добавить логгер

        // Клиенту — только общее сообщение без внутренних деталей
        var problem = ProblemDetail.forStatusAndDetail(
            HttpStatus.INTERNAL_SERVER_ERROR,
            "An unexpected error occurred. Please try again later.");
        problem.setInstance(URI.create(extractPath(request)));
        return problem;
    }

    private String extractPath(WebRequest request) {
        var desc = request.getDescription(false);
        return desc.startsWith("uri=") ? desc.substring(4) : desc;
    }
}

package com.example.taskflow.task;

import com.example.taskflow.security.SecurityUtils;
import jakarta.validation.Valid;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.data.web.PageableDefault;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.net.URI;

@RestController
@RequestMapping("/api/v1/tasks")
public class TaskController {

    private final TaskService taskService;

    public TaskController(TaskService taskService) {
        this.taskService = taskService;
    }

    // GET /api/v1/tasks?projectId=1&page=0&size=20&sort=createdAt,desc
    @GetMapping
    public Page<TaskResponse> list(
            @RequestParam Long projectId,
            @PageableDefault(size = 20, sort = "createdAt",
                             direction = Sort.Direction.DESC) Pageable pageable) {
        return taskService.getProjectTasks(projectId, pageable);
    }

    // GET /api/v1/tasks/42
    @GetMapping("/{id}")
    public TaskResponse getById(@PathVariable Long id) {
        return taskService.getTask(id);
    }

    // POST /api/v1/tasks → 201 Created + Location header
    @PostMapping
    public ResponseEntity<TaskResponse> create(
            @Valid @RequestBody CreateTaskRequest request) {
        var task = taskService.createTask(SecurityUtils.currentUserId(), request);
        return ResponseEntity
                .created(URI.create("/api/v1/tasks/" + task.id()))
                .body(task);
    }

    // PATCH /api/v1/tasks/42 — полное обновление полей задачи
    @PatchMapping("/{id}")
    public TaskResponse update(
            @PathVariable Long id,
            @Valid @RequestBody UpdateTaskRequest request) {
        return taskService.updateTask(id, request);
    }

    // PATCH /api/v1/tasks/42/status — специальный эндпоинт для смены статуса
    @PatchMapping("/{id}/status")
    public TaskResponse changeStatus(
            @PathVariable Long id,
            @Valid @RequestBody ChangeStatusRequest request) {
        return taskService.changeStatus(id, request);
    }

    // PATCH /api/v1/tasks/42/assignee — назначить/снять исполнителя
    @PatchMapping("/{id}/assignee")
    public TaskResponse assign(
            @PathVariable Long id,
            @RequestBody AssignTaskRequest request) {
        return taskService.assignTask(id, request);
    }

    // DELETE /api/v1/tasks/42 → 204 No Content
    @DeleteMapping("/{id}")
    @ResponseStatus(HttpStatus.NO_CONTENT)
    public void delete(@PathVariable Long id) {
        taskService.deleteTask(id);
    }
}

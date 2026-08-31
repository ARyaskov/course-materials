package com.example.taskflow.notification;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.retry.annotation.Backoff;
import org.springframework.retry.annotation.Recover;
import org.springframework.retry.annotation.Retryable;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpServerErrorException;
import org.springframework.web.client.ResourceAccessException;
import org.springframework.web.client.RestClient;

@Component
public class HttpNotificationGateway implements NotificationGateway {

    private static final Logger log = LoggerFactory.getLogger(HttpNotificationGateway.class);

    private final RestClient restClient;

    public HttpNotificationGateway(RestClient notificationRestClient) {
        this.restClient = notificationRestClient;
    }

    @Override
    @Retryable(
        retryFor = {HttpServerErrorException.class, ResourceAccessException.class},
        maxAttempts = 3,
        backoff = @Backoff(delay = 1000, multiplier = 2.0, maxDelay = 10000, random = true)
    )
    public void notifyTaskCreated(Long userId, Long taskId, String taskTitle) {
        var request = new NotificationRequest(userId, taskId, "TASK_CREATED", taskTitle);
        log.debug("Sending TASK_CREATED notification: userId={}, taskId={}", userId, taskId);
        restClient.post()
                  .uri("/api/v1/notifications")
                  .body(request)
                  .retrieve()
                  .toBodilessEntity();
        log.debug("Notification sent successfully");
    }

    @Override
    @Retryable(
        retryFor = {HttpServerErrorException.class, ResourceAccessException.class},
        maxAttempts = 3,
        backoff = @Backoff(delay = 1000, multiplier = 2.0, maxDelay = 10000)
    )
    public void notifyTaskAssigned(Long assigneeId, Long taskId, String taskTitle) {
        var request = new NotificationRequest(assigneeId, taskId, "TASK_ASSIGNED", taskTitle);
        restClient.post()
                  .uri("/api/v1/notifications")
                  .body(request)
                  .retrieve()
                  .toBodilessEntity();
    }

    @Recover
    public void recover(RuntimeException ex, Long userId, Long taskId, String taskTitle) {
        log.error("Notification service unavailable after retries. userId={}, taskId={}, type=TASK_CREATED",
                  userId, taskId, ex);
        // TODO: сохранить в outbox для повторной отправки
    }
}

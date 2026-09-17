# Типы, упомянутые в уроках, но не показанные целиком

Каталог `project/helpdesk` материализует то, что показано в листингах курса. Перечисленные ниже
классы и интерфейсы встречаются в импортах и сигнатурах, но их собственного листинга в уроках нет:
тема урока была другой. При переносе проекта в рабочее состояние их дописывают — сигнатуры
восстанавливаются по местам использования.

Всего 50 типов.

### `App\Application\Auth`

- `LoginInput`

### `App\Application\Import`

- `ImportRunRepository`
- `TicketRowMapper`

### `App\Application\Import\Message`

- `ImportBatchMessage`

### `App\Application\Notification`

- `NotificationDispatcher`

### `App\Application\Report\Message`

- `ExportReportMessage`

### `App\Application\Survey\Message`

- `SendSurveyMessage`

### `App\Application\Ticket`

- `ChangeStatusInput`
- `TicketListItem`
- `TicketReadModel`
- `TicketWithRelations`

### `App\Application\Ticket\Message`

- `NotifyStatusChangedMessage`
- `SendSurveyHandler`
- `SendSurveyMessage`
- `SlaReminderMessage`
- `TicketClosedMessage`

### `App\Application\Webhook\Message`

- `SendWebhookMessage`

### `App\Console`

- `ImportStatusCommand`
- `QueueRetryFailedCommand`
- `ScheduleRunCommand`

### `App\Domain\Audit`

- `AuditEntry`
- `AuditRepositoryInterface`

### `App\Domain\Auth`

- `IssuedToken`
- `RefreshTokenRepositoryInterface`
- `TokenPair`

### `App\Domain\Comment`

- `Comment`
- `CommentRepositoryInterface`

### `App\Domain\Directory`

- `Employee`

### `App\Domain\Moderation`

- `BlacklistProviderInterface`

### `App\Domain\RateLimit`

- `RateLimitDecision`
- `RateLimiterInterface`

### `App\Domain\Report`

- `SummaryRepositoryInterface`
- `TicketSummary`

### `App\Domain\Storage`

- `AttachmentStorageInterface`

### `App\Domain\Ticket`

- `Attachment`
- `AttachmentRepositoryInterface`

### `App\Domain\Webhook`

- `WebhookSubscriptionRepositoryInterface`

### `App\Infrastructure\Db`

- `ReadWriteConnection`

### `App\Infrastructure\Log`

- `LogRequestSummary`

### `App\Infrastructure\Mail`

- `SmtpMailer`

### `App\Infrastructure\Notification`

- `EmailChannel`
- `WebhookChannel`

### `App\Infrastructure\Rbac`

- `CachedItemsStorage`

### `App\Infrastructure\Report`

- `DbSummaryRepository`

### `App\Infrastructure\Router`

- `AbsoluteUrlGenerator`

### `App\Infrastructure\Storage\S3`

- `S3ClientInterface`

### `App\Infrastructure\Validation\Rule`

- `NotCompromisedPassword`

### `App\Tests\Support`

- `InMemoryUserRepository`
- `StubAccessTokenService`
- `StubDirectoryClient`

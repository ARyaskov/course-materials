# Карта «урок → файлы» — helpdesk

Таблица построена по листингам курса: в каждой строке — урок и файлы проекта, которые в нём разбираются.
Файлы, собранные из нескольких уроков (`bootstrap/app.php`, `routes/*`, `config/*`, `app/Providers/AppServiceProvider.php`), отмечены отдельно в README.

## Глава 1

| Урок | Файлы |
| --- | --- |
| 1.1 | `app/Domain/TicketDraft.php`<br>`app/Domain/TicketPriority.php` |
| 1.3 | `app/Http/Controllers/Web/TicketPageController.php`<br>`app/Http/Middleware/ForceJsonResponse.php`<br>`tests/Feature/TicketIndexTest.php` |
| 1.4 | `database/migrations/2026_01_10_000200_create_tickets_table.php` |

## Глава 2

| Урок | Файлы |
| --- | --- |
| 2.1 | `scripts/check-env.php` |
| 2.3 | `scripts/close-stale-tickets.php` |
| 2.5 | `docker/nginx.conf` |

## Глава 3

| Урок | Файлы |
| --- | --- |
| 3.1 | `app/Http/Middleware/RecordApiMetrics.php` |
| 3.2 | `app/Domain/TicketSummary.php`<br>`app/Http/Queries/TicketListQuery.php` |
| 3.3 | `app/Domain/Money.php` |

## Глава 4

| Урок | Файлы |
| --- | --- |
| 4.1 | `app/Domain/Ticket.php`<br>`app/Domain/TicketMetrics.php` |
| 4.3 | `app/Jobs/ProcessTicket.php`<br>`app/Support/TenantContext.php` |
| 4.4 | `app/Notifications/Channel.php`<br>`app/Notifications/MailChannel.php`<br>`app/Notifications/WebhookChannel.php` |
| 4.5 | `app/Contracts/ExportFormat.php`<br>`app/Exports/CsvExport.php`<br>`app/Exports/JsonExport.php`<br>`app/Http/Controllers/TicketExportController.php`<br>`app/Notifications/MailNotifier.php`<br>`app/Notifications/QueueNotifier.php` |
| 4.6 | `app/Models/Concerns/HasUuid.php`<br>`app/Services/TicketStatsService.php`<br>`app/Support/Concerns/Cacheable.php` |
| 4.7 | `app/Repositories/TicketRepository.php` |

## Глава 5

| Урок | Файлы |
| --- | --- |
| 5.1 | `app/DTO/Pagination.php` |
| 5.2 | `app/Support/Pipeline.php` |
| 5.3 | `app/Attributes/AuditAction.php`<br>`app/Console/Commands/BuildAuditMap.php` |
| 5.4 | `app/Enums/Concerns/HasLabel.php`<br>`app/Enums/TicketStatus.php`<br>`app/Http/Requests/UpdateTicketStatusRequest.php` |
| 5.5 | `app/Domain/DateRange.php`<br>`app/Domain/Email.php` |
| 5.6 | `app/Console/Commands/ImportTickets.php`<br>`app/Support/CsvReader.php` |

## Глава 6

| Урок | Файлы |
| --- | --- |
| 6.2 | `tests/Feature/TicketMethodsTest.php` |
| 6.3 | `tests/Feature/ErrorFormatTest.php` |
| 6.4 | `tests/Feature/TicketResponseShapeTest.php` |
| 6.5 | `app/Http/Queries/TicketQuery.php`<br>`database/migrations/..._add_ticket_indexes.php`<br>`tests/Feature/TicketListTest.php` |
| 6.6 | `app/Http/Controllers/Api/V2/TicketController.php`<br>`app/Http/Middleware/DeprecateApiVersion.php`<br>`app/Http/Middleware/ResolveApiVersion.php`<br>`app/Http/Resources/V1/TicketResource.php`<br>`app/Http/Resources/V2/TicketResource.php`<br>`tests/Feature/Api/V1/ContractTest.php` |

## Глава 7

| Урок | Файлы |
| --- | --- |
| 7.3 | `tests/Feature/CloseStaleTicketsTest.php` |
| 7.6 | `app/Enums/TicketPriority.php`<br>`tests/Feature/TicketApiTest.php` |

## Глава 8

| Урок | Файлы |
| --- | --- |
| 8.1 | `app/Http/Controllers/NotFoundController.php`<br>`tests/Feature/RoutesTest.php` |
| 8.2 | `tests/Feature/RouteBindingTest.php` |
| 8.3 | `tests/Feature/TicketControllerTest.php` |
| 8.4 | `app/Http/Middleware/EnsureIdempotency.php`<br>`app/Http/Middleware/EnsureRole.php`<br>`app/Http/Middleware/EnsureUserIsAgent.php`<br>`app/Http/Middleware/RecordAudit.php`<br>`tests/Feature/MiddlewareTest.php` |
| 8.5 | `app/Http/Requests/UpdateTicketRequest.php`<br>`tests/Feature/StoreTicketValidationTest.php` |

## Глава 9

| Урок | Файлы |
| --- | --- |
| 9.2 | `tests/Feature/MigrationsTest.php` |
| 9.3 | `database/migrations/2026_09_07_120000_create_tickets_table.php`<br>`tests/Feature/SchemaConstraintsTest.php` |
| 9.4 | `database/seeders/DatabaseSeeder.php`<br>`database/seeders/TagSeeder.php`<br>`database/seeders/TicketSeeder.php`<br>`database/seeders/UserSeeder.php` |
| 9.5 | `database/migrations/2026_09_07_130000_add_sla_to_tickets_table.php`<br>`tests/Feature/MigrationsRollbackTest.php` |
| 9.6 | `database/migrations/2026_09_08_120000_add_index_to_tickets.php` |

## Глава 10

| Урок | Файлы |
| --- | --- |
| 10.1 | `app/Models/Export.php`<br>`app/Models/LegacyTicket.php`<br>`app/Models/Scopes/VisibleToUserScope.php`<br>`database/migrations/..._create_exports_table.php`<br>`tests/Feature/TicketModelTest.php` |
| 10.2 | `tests/Feature/TicketCrudTest.php` |
| 10.3 | `tests/Feature/MassAssignmentTest.php` |
| 10.4 | `app/Casts/AddressCast.php`<br>`app/Casts/MoneyCast.php`<br>`tests/Feature/TicketCastsTest.php` |
| 10.5 | `app/Console/Commands/PurgeTrashedTickets.php`<br>`database/migrations/..._create_tickets_table.php`<br>`tests/Feature/SoftDeleteTest.php` |
| 10.6 | `tests/Feature/TicketStatsQueryTest.php` |

## Глава 11

| Урок | Файлы |
| --- | --- |
| 11.1 | `app/Models/AgentProfile.php`<br>`app/Models/Comment.php`<br>`database/migrations/..._create_comments_table.php`<br>`tests/Feature/RelationsTest.php` |
| 11.2 | `app/Models/Tag.php`<br>`app/Models/TicketTag.php`<br>`database/migrations/..._create_ticket_tag_table.php`<br>`tests/Feature/TagsRelationTest.php` |
| 11.3 | `tests/Feature/EagerLoadingTest.php`<br>`tests/Feature/TicketListQueriesTest.php` |
| 11.4 | `app/Http/Controllers/TicketStatsController.php`<br>`app/Queries/AgentPerformanceQuery.php`<br>`tests/Feature/AggregatesTest.php` |
| 11.5 | `app/Exceptions/StaleDataException.php`<br>`tests/Feature/TransactionsTest.php` |
| 11.6 | `app/Models/Ticket.php`<br>`app/Models/User.php`<br>`app/Observers/TicketObserver.php`<br>`app/Services/TicketAssignmentService.php`<br>`database/migrations/2026_09_10_000100_create_tags_table.php`<br>`database/migrations/2026_09_10_000200_create_ticket_tag_table.php`<br>`database/migrations/2026_09_10_000300_create_ticket_subscriptions_table.php`<br>`database/migrations/2026_09_10_000400_create_agent_profiles_table.php`<br>`tests/Feature/DomainModelTest.php` |

## Глава 12

| Урок | Файлы |
| --- | --- |
| 12.1 | `tests/Feature/TicketResourceTest.php` |
| 12.2 | `app/Http/Resources/CommentResource.php`<br>`app/Http/Resources/MoneyResource.php`<br>`app/Http/Resources/UserResource.php`<br>`app/Http/Responses/TicketCreated.php` |
| 12.3 | `app/Http/Queries/Pagination.php`<br>`app/Http/Resources/TicketStatsResource.php`<br>`tests/Feature/PaginationTest.php` |
| 12.4 | `app/DTO/TicketData.php`<br>`app/DTO/TicketFilters.php`<br>`app/DTO/TicketStats.php`<br>`tests/Unit/TicketDataTest.php` |
| 12.5 | `app/Http/Controllers/Controller.php`<br>`lang/ru/errors.php`<br>`tests/Feature/ApiContractTest.php` |
| 12.6 | `app/Http/Controllers/TicketController.php`<br>`app/Http/Requests/TicketIndexRequest.php`<br>`app/Http/Resources/TicketCollection.php`<br>`app/Http/Resources/TicketListResource.php`<br>`app/Http/Resources/TicketResource.php`<br>`app/Queries/TicketQuery.php`<br>`tests/Feature/TicketApiContractTest.php` |

## Глава 13

| Урок | Файлы |
| --- | --- |
| 13.1 | `app/DTO/AuthResult.php`<br>`app/Enums/UserRole.php`<br>`app/Exceptions/InvalidCredentialsException.php`<br>`app/Http/Controllers/AuthController.php`<br>`app/Http/Requests/ChangePasswordRequest.php`<br>`app/Http/Requests/LoginRequest.php`<br>`app/Http/Requests/RegisterRequest.php`<br>`app/Services/AuthService.php`<br>`tests/Feature/AuthTest.php` |
| 13.2 | `app/Http/Controllers/PasswordResetController.php`<br>`tests/Feature/PasswordTest.php` |
| 13.3 | `app/Enums/TokenAbility.php`<br>`app/Models/AccessToken.php`<br>`database/migrations/..._create_personal_access_tokens_table.php`<br>`tests/Feature/SanctumTest.php` |
| 13.4 | `app/Policies/TicketPolicy.php`<br>`tests/Feature/TicketPolicyTest.php` |
| 13.5 | `app/Http/Middleware/DetectEnumeration.php`<br>`app/Http/Middleware/ThrottleByCost.php`<br>`tests/Feature/RateLimitTest.php` |
| 13.6 | `app/Http/Middleware/SecurityHeaders.php`<br>`tests/Feature/SecurityTest.php` |

## Глава 14

| Урок | Файлы |
| --- | --- |
| 14.1 | `lang/ru/validation.php`<br>`tests/Feature/ValidationRulesTest.php` |
| 14.2 | `app/Http/Requests/ApiRequest.php`<br>`app/Http/Requests/Concerns/TicketRules.php`<br>`app/Http/Requests/StoreTicketRequest.php`<br>`app/Rules/NotProfane.php`<br>`app/Rules/TagsFromSameSection.php`<br>`tests/Feature/CustomValidationTest.php`<br>`tests/Unit/NotProfaneTest.php` |
| 14.3 | `app/Exceptions/TicketLimitExceededException.php`<br>`tests/Feature/ExceptionHandlingTest.php` |
| 14.4 | `app/Exceptions/AgentOverloadedException.php`<br>`app/Exceptions/DomainException.php`<br>`app/Exceptions/ExternalServiceUnavailableException.php`<br>`app/Exceptions/InvalidStatusTransitionException.php`<br>`app/Exceptions/TicketAlreadyClosedException.php`<br>`app/Services/DirectoryClient.php`<br>`tests/Feature/DomainErrorsTest.php` |
| 14.5 | `app/Http/Middleware/ApiHeaders.php`<br>`app/Listeners/LogSecurityEvents.php`<br>`app/Support/LogSanitizer.php`<br>`tests/Feature/LoggingTest.php` |
| 14.6 | `app/Enums/ErrorCode.php`<br>`app/Exceptions/ApiExceptionRenderer.php`<br>`app/Http/Controllers/ApiSchemaController.php`<br>`tests/Feature/ErrorContractTest.php` |

## Глава 15

| Урок | Файлы |
| --- | --- |
| 15.1 | `app/Console/Commands/CloseStaleTickets.php`<br>`app/Http/Controllers/Ticket/CloseTicketController.php`<br>`app/Http/Requests/CloseTicketRequest.php`<br>`tests/Feature/CloseTicketTest.php` |
| 15.2 | `app/Actions/Ticket/CloseTicket.php`<br>`app/Services/CommentWriter.php`<br>`app/Services/TagResolver.php`<br>`app/Services/TicketEscalationService.php`<br>`app/Services/TicketService.php`<br>`tests/Unit/TicketServiceTest.php` |
| 15.3 | `app/Contracts/SearchIndex.php`<br>`app/Domain/Ticket/TicketRepository.php`<br>`app/Repositories/EloquentTicketRepository.php`<br>`app/Repositories/TicketRepositoryInterface.php`<br>`tests/Doubles/FakeAgentDirectory.php`<br>`tests/Feature/DirectoryTest.php` |
| 15.4 | `app/Providers/SearchServiceProvider.php`<br>`app/Services/NotificationDispatcher.php`<br>`tests/Feature/ContainerTest.php`<br>`tests/Feature/NotificationTest.php` |
| 15.5 | `app/Contracts/Notifier.php`<br>`app/Contracts/PaymentGateway.php`<br>`app/Services/Notifications/CircuitBreakerNotifier.php`<br>`app/Services/Notifications/LoggingNotifier.php`<br>`app/Services/Notifications/MailNotifier.php`<br>`app/Services/Notifications/NotifierFactory.php`<br>`app/Services/Notifications/QueueNotifier.php`<br>`app/Services/Notifications/WebhookNotifier.php`<br>`tests/Feature/NotifierTest.php` |
| 15.6 | `app/Providers/DomainServiceProvider.php`<br>`tests/Architecture/StructureTest.php` |

## Глава 16

| Урок | Файлы |
| --- | --- |
| 16.1 | `tests/Feature/QueueBasicsTest.php` |
| 16.2 | `app/Jobs/GenerateTicketExport.php`<br>`app/Jobs/Middleware/LogJobDuration.php`<br>`tests/Feature/JobsTest.php` |
| 16.3 | `redis.conf`<br>`tests/Feature/RedisQueueTest.php` |
| 16.4 | `app/Console/Commands/CheckFailedJobs.php`<br>`app/Jobs/SyncTicketToCrm.php`<br>`tests/Feature/JobReliabilityTest.php` |
| 16.5 | `app/Console/Commands/CheckSchedulerHealth.php`<br>`app/Console/Commands/EscalateOverdueTickets.php`<br>`app/Jobs/BuildDailyDigest.php`<br>`tests/Feature/SchedulerTest.php` |
| 16.6 | `app/Console/Commands/BackfillTicketSla.php`<br>`app/Console/Commands/DispatchTicketReindex.php`<br>`app/Events/TicketClosed.php`<br>`app/Http/Controllers/BatchStatusController.php`<br>`app/Jobs/NotifyTicketClosed.php`<br>`app/Jobs/ReindexTicket.php`<br>`app/Listeners/HandleTicketClosed.php`<br>`database/migrations/..._create_notifications_table.php`<br>`tests/Feature/NotificationPipelineTest.php` |

## Глава 17

| Урок | Файлы |
| --- | --- |
| 17.1 | `app/Console/Commands/WarmCache.php`<br>`app/Queries/TicketStatsQuery.php`<br>`app/Support/CacheMetrics.php`<br>`tests/Feature/CacheTest.php` |
| 17.2 | `app/Console/Commands/CacheInspect.php`<br>`app/Observers/UserObserver.php`<br>`app/Support/TicketCache.php`<br>`tests/Feature/CacheInvalidationTest.php` |
| 17.3 | `app/Console/Commands/PruneOrphanedFiles.php`<br>`app/Http/Resources/AttachmentResource.php`<br>`app/Models/Attachment.php`<br>`app/Observers/AttachmentObserver.php`<br>`app/Support/AttachmentPath.php`<br>`tests/Feature/StorageTest.php` |
| 17.4 | `app/Http/Controllers/AttachmentController.php`<br>`app/Http/Controllers/UploadUrlController.php`<br>`app/Http/Middleware/DetectPostSizeExceeded.php`<br>`app/Http/Requests/StoreAttachmentRequest.php`<br>`app/Jobs/ProcessAttachment.php`<br>`app/Services/AttachmentService.php`<br>`tests/Feature/AttachmentUploadTest.php` |
| 17.5 | `app/Contracts/AgentDirectory.php`<br>`app/DTO/AgentInfo.php`<br>`app/Providers/IntegrationServiceProvider.php`<br>`app/Services/Directory/HttpAgentDirectory.php`<br>`tests/Feature/DirectoryClientTest.php` |
| 17.6 | `app/Console/Commands/IntegrationsHealth.php`<br>`app/Services/Crm/HttpCrmClient.php`<br>`app/Services/Directory/CachedFallbackDirectory.php`<br>`app/Support/CircuitBreaker.php`<br>`tests/Feature/ResilienceTest.php` |

## Глава 18

| Урок | Файлы |
| --- | --- |
| 18.1 | `tests/Datasets/Users.php`<br>`tests/Feature/TestSetupTest.php`<br>`tests/Feature/Tickets/CloseTicketTest.php`<br>`tests/TestCase.php` |
| 18.2 | `tests/Doubles/FakeNotifier.php`<br>`tests/Integration/NotificationTest.php`<br>`tests/Integration/TicketServiceTest.php`<br>`tests/Unit/DTO/TicketFiltersTest.php`<br>`tests/Unit/Domain/MoneyTest.php`<br>`tests/Unit/Enums/TicketStatusTest.php`<br>`tests/Unit/Models/TicketOverdueTest.php`<br>`tests/Unit/Rules/NotProfaneTest.php`<br>`tests/Unit/SanityTest.php` |
| 18.3 | `tests/Feature/Tickets/CreateTicketTest.php`<br>`tests/Feature/Tickets/IdempotencyTest.php`<br>`tests/Feature/Tickets/TicketListTest.php` |
| 18.4 | `database/factories/CommentFactory.php`<br>`database/factories/TicketFactory.php`<br>`database/factories/UserFactory.php`<br>`database/seeders/TestSeeder.php`<br>`tests/Feature/DatabaseIsolationTest.php`<br>`tests/Feature/FactoriesTest.php`<br>`tests/Pest.php` |
| 18.5 | `tests/Architecture/AuthorizationTest.php`<br>`tests/Feature/Authorization/FieldVisibilityTest.php`<br>`tests/Feature/Authorization/SanityTest.php`<br>`tests/Feature/Authorization/SystemActionsTest.php`<br>`tests/Feature/Authorization/TicketEndpointsAccessTest.php`<br>`tests/Feature/Authorization/TicketPolicyMatrixTest.php`<br>`tests/Feature/Authorization/TicketStatePermissionsTest.php`<br>`tests/Feature/Authorization/TicketVisibilityTest.php`<br>`tests/Feature/Authorization/TokenAbilitiesTest.php` |
| 18.6 | `tests/Feature/Exports/ExportChainTest.php`<br>`tests/Feature/Notifications/MailTest.php`<br>`tests/Feature/Scheduler/EscalationTest.php`<br>`tests/Feature/Tickets/CloseTicketQueueTest.php`<br>`tests/Integration/Directory/HttpAgentDirectoryTest.php`<br>`tests/Integration/Jobs/NotifyTicketClosedTest.php` |
| 18.7 | `tests/Architecture/CoverageTest.php`<br>`tests/Architecture/LayersTest.php`<br>`tests/Datasets/InvalidPayloads.php`<br>`tests/Datasets/Roles.php`<br>`tests/Feature/Contract/EnvelopeTest.php`<br>`tests/Feature/Contract/PerformanceTest.php`<br>`tests/Feature/TicketLifecycleTest.php` |

## Глава 19

| Урок | Файлы |
| --- | --- |
| 19.2 | `docker/postgres/init.sql` |
| 19.3 | `docker/nginx/default.conf` |
| 19.4 | `app/Console/Commands/QueueHealth.php`<br>`deploy.sh`<br>`tests/Feature/Infrastructure/QueueConfigTest.php` |
| 19.5 | `app/Console/Commands/CheckEnvironment.php`<br>`app/Console/Commands/RotateEncryptedFields.php`<br>`docker/entrypoint.sh`<br>`tests/Architecture/ConfigTest.php`<br>`tests/Feature/Infrastructure/EnvironmentTest.php` |
| 19.6 | `docker/nginx/prod.conf` |
| 19.7 | `app/Console/Commands/BackfillStatus.php`<br>`app/Jobs/BackfillTicketSubjects.php`<br>`database/migrations/2026_03_11_100000_add_subject_to_tickets.php`<br>`database/migrations/2026_03_11_101500_add_sla_hours_to_tickets.php`<br>`database/migrations/2026_03_11_101800_create_ticket_escalations_table.php`<br>`database/migrations/2026_03_11_102000_add_index_to_tickets_status.php`<br>`database/migrations/2026_03_12_090000_backfill_ticket_subject.php`<br>`database/migrations/2026_03_12_091000_dispatch_subject_backfill.php`<br>`database/migrations/2026_03_20_090000_drop_title_from_tickets.php`<br>`database/migrations/README.md`<br>`tests/Feature/MigrationTest.php` |

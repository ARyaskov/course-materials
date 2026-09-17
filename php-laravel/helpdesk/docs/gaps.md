# Что не вошло в проект

Уроки упоминают эти классы как соседей по коду, но целиком их не показывают. Проект — материализация листингов, поэтому здесь их нет: дописать их по сигнатурам из соседних файлов — хорошее упражнение после соответствующей главы.

| Класс | Где упоминается |
| --- | --- |
| `App\Contracts\CrmClient` | `app/Services/Crm/HttpCrmClient.php` |
| `App\DTO\ChargeResult` | `app/Contracts/PaymentGateway.php` |
| `App\Domain\Address` | `app/Casts/AddressCast.php` |
| `App\Events\TicketAssigned` | `app/Services/TicketService.php` |
| `App\Events\TicketCreated` | `app/Services/TicketService.php`, `tests/Integration/TicketServiceTest.php`, `tests/Unit/TicketServiceTest.php` |
| `App\Exceptions\AttachmentRejectedException` | `app/Services/AttachmentService.php` |
| `App\Exceptions\TicketAlreadyAssignedException` | `app/Services/TicketAssignmentService.php`, `app/Services/TicketService.php` |
| `App\Exceptions\TicketNotFoundException` | `app/Repositories/TicketRepository.php` |
| `App\Http\Controllers\CommentController` | `routes/api.php` |
| `App\Http\Requests\RequestUploadUrlRequest` | `app/Http/Controllers/UploadUrlController.php` |
| `App\Jobs\NotifyTicketCreated` | `tests/Feature/TransactionsTest.php` |
| `App\Jobs\SendNotification` | `app/Notifications/QueueNotifier.php`, `app/Services/Notifications/QueueNotifier.php` |
| `App\Mail\TicketClosedMail` | `tests/Feature/Notifications/MailTest.php` |
| `App\Models\AuditLog` | `app/Http/Middleware/RecordAudit.php` |
| `App\Models\Notification` | `app/Jobs/NotifyTicketClosed.php`, `tests/Feature/JobReliabilityTest.php`, `tests/Feature/NotificationPipelineTest.php` и др. |
| `App\Observers\CommentObserver` | `app/Providers/DomainServiceProvider.php` |
| `App\Services\Search\RedisSearchIndex` | `app/Providers/SearchServiceProvider.php` |

## Учебные варианты, лежащие рядом

Некоторые файлы — не части одного приложения, а сравниваемые в уроках варианты:

- `app/Repositories/*` — из урока 15.3 «когда репозиторий оправдан, а когда мешает»;
- `app/Domain/{Ticket,TicketDraft,TicketPriority}.php` — объекты предметной области из глав 1 и 4, показанные до появления Eloquent-моделей;
- `docs/examples/migrations/*` — миграции из главы 19 (переименование колонки в три релиза, `CREATE INDEX CONCURRENTLY`, перенос данных задачей). Они относятся к другой схеме и не входят в набор миграций HelpDesk;
- `scripts/close-stale-tickets.php` — вариант «на голом PHP» из главы 2, позже заменённый командой `app/Console/Commands/CloseStaleTickets.php`.

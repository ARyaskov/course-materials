<?php
// app/Models/Ticket.php
declare(strict_types=1);

namespace App\Models;

use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Models\Concerns\HasUuid;
use App\Observers\TicketObserver;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Attributes\ObservedBy;
use Illuminate\Database\Eloquent\Attributes\Scope;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\Relations\MorphMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * @property int $id
 * @property string $subject
 * @property TicketStatus $status
 * @property TicketPriority $priority
 * @property int $author_id
 * @property int|null $assignee_id
 * @property int $version
 * @property CarbonImmutable|null $resolved_at
 * @property-read User $author
 * @property-read User|null $assignee
 * @property-read Collection<int, Comment> $comments
 * @property-read Collection<int, Tag> $tags
 * @property-read Collection<int, User> $subscribers
 */
#[ObservedBy(TicketObserver::class)]
final class Ticket extends Model
{
    use HasFactory;
    use HasUuid;
    use SoftDeletes;

    protected $fillable = [
        'subject', 'body', 'priority', 'status', 'assignee_id',
        'resolved_at', 'resolution', 'due_at', 'first_response_at',
    ];

    /**
     * Значения по умолчанию на уровне модели: в базе они тоже заданы,
     * но объект должен знать их сразу после create(), не дожидаясь refresh().
     */
    protected $attributes = [
        'status' => 'open',
        'priority' => 'normal',
        'version' => 1,
    ];

    protected function casts(): array
    {
        return [
            'status'      => TicketStatus::class,
            'priority'    => TicketPriority::class,
            'resolved_at' => 'immutable_datetime',
            'due_at' => 'immutable_datetime',
            'first_response_at' => 'immutable_datetime',
            'sla_hours' => 'integer',
            'version' => 'integer',
        ];
    }

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }

    public function assignee(): BelongsTo
    {
        return $this->belongsTo(User::class, 'assignee_id')->withDefault(['name' => 'Не назначен']);
    }

    public function comments(): HasMany
    {
        return $this->hasMany(Comment::class);
    }

    public function latestComment(): HasOne
    {
        return $this->hasOne(Comment::class)->latestOfMany();
    }

    public function tags(): BelongsToMany
    {
        // таблица задана явно: по соглашению Eloquent искал бы tag_ticket
        return $this->belongsToMany(Tag::class, 'ticket_tag')
            ->withPivot(['attached_by', 'created_at']);
    }

    public function subscribers(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'ticket_subscriptions')
            ->withPivot(['is_muted', 'reason'])
            ->withTimestamps();
    }

    public function attachments(): MorphMany
    {
        return $this->morphMany(Attachment::class, 'attachable');
    }

    /** Крайний срок первого ответа: создание плюс SLA приоритета. */
    public function slaDeadline(): CarbonImmutable
    {
        return CarbonImmutable::parse($this->created_at)->addHours($this->sla_hours);
    }

    public function isOverdue(): bool
    {
        if ($this->status->isFinal()) {
            return false;
        }

        return $this->first_response_at === null && $this->slaDeadline()->isPast();
    }

    #[Scope]
    protected function open(Builder $query): void
    {
        $query->whereNot('status', TicketStatus::Closed);
    }

    #[Scope]
    protected function unanswered(Builder $query): void
    {
        $query->whereDoesntHave(
            'comments',
            fn (Builder $q) => $q->where('is_system', false)
                ->whereHas('author', fn (Builder $a) => $a->where('role', 'agent')),
        );
    }

    #[Scope]
    protected function visibleTo(Builder $query, User $user): void
    {
        $query->unless($user->isAgent(), fn (Builder $q) => $q->where('author_id', $user->id));
    }
}

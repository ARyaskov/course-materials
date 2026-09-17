<?php
// app/DTO/TicketFilters.php
declare(strict_types=1);

namespace App\DTO;

use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use Carbon\CarbonImmutable;
use Illuminate\Http\Request;

final readonly class TicketFilters
{
    /** @param  list<TicketPriority>  $priorities */
    public function __construct(
        public ?TicketStatus $status = null,
        public array $priorities = [],
        public ?int $assigneeId = null,
        public bool $unassignedOnly = false,
        public bool $unansweredOnly = false,
        public ?CarbonImmutable $createdFrom = null,
        public ?CarbonImmutable $createdTo = null,
        public ?string $search = null,
    ) {
    }

    public static function fromRequest(Request $request): self
    {
        return new self(
            status: $request->enum('status', TicketStatus::class),
            priorities: array_values(array_filter(
                array_map(TicketPriority::tryFrom(...), $request->array('priority'))
            )),
            assigneeId: $request->has('assignee_id') ? $request->integer('assignee_id') : null,
            unassignedOnly: $request->boolean('unassigned'),
            unansweredOnly: $request->boolean('unanswered'),
            createdFrom: $request->date('created_from')?->toImmutable(),
            createdTo: $request->date('created_to')?->toImmutable(),
            search: $request->string('q')->trim()->toString() ?: null,
        );
    }

    public function isEmpty(): bool
    {
        return $this->status === null
            && $this->priorities === []
            && $this->assigneeId === null
            && ! $this->unassignedOnly
            && ! $this->unansweredOnly
            && $this->search === null;
    }

    /** @return array<string, mixed> — для ключа кэша и для meta ответа */
    public function toArray(): array
    {
        return array_filter([
            'status'     => $this->status?->value,
            'priorities' => array_map(fn (TicketPriority $p): string => $p->value, $this->priorities),
            'assignee_id' => $this->assigneeId,
            'unassigned' => $this->unassignedOnly ?: null,
            'unanswered' => $this->unansweredOnly ?: null,
            'q'          => $this->search,
        ]);
    }

    public function cacheKey(): string
    {
        return 'tickets:' . md5(json_encode($this->toArray(), JSON_THROW_ON_ERROR));
    }
}

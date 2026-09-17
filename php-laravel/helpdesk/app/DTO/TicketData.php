<?php
// app/DTO/TicketData.php
declare(strict_types=1);

namespace App\DTO;

use App\Enums\TicketPriority;
use App\Http\Requests\StoreTicketRequest;
use Carbon\CarbonImmutable;
use InvalidArgumentException;

final readonly class TicketData
{
    /** @param  list<string>  $tags */
    public function __construct(
        public string $subject,
        public string $body,
        public TicketPriority $priority = TicketPriority::Normal,
        public ?int $assigneeId = null,
        public array $tags = [],
        public ?CarbonImmutable $dueAt = null,
    ) {
        if ($priority === TicketPriority::Critical && $assigneeId === null) {
            throw new InvalidArgumentException('Критичная заявка требует исполнителя');
        }

        if (count($tags) > 5) {
            throw new InvalidArgumentException('Не больше пяти меток');
        }
    }

    public static function fromRequest(StoreTicketRequest $request): self
    {
        return new self(
            subject: $request->string('subject')->trim()->toString(),
            body: $request->string('body')->toString(),
            priority: $request->enum('priority', TicketPriority::class) ?? TicketPriority::Normal,
            assigneeId: $request->has('assignee_id') ? $request->integer('assignee_id') : null,
            tags: array_values(array_unique($request->array('tags'))),
            dueAt: $request->date('due_at')?->toImmutable(),
        );
    }

    /** @param  array<string, mixed>  $data */
    public static function fromArray(array $data): self
    {
        return new self(
            subject: (string) $data['subject'],
            body: (string) $data['body'],
            priority: TicketPriority::from($data['priority'] ?? 'normal'),
            assigneeId: isset($data['assignee_id']) ? (int) $data['assignee_id'] : null,
            tags: $data['tags'] ?? [],
        );
    }

    /** @return array<string, mixed> */
    public function toAttributes(): array
    {
        return array_filter([
            'subject'     => $this->subject,
            'body'        => $this->body,
            'priority'    => $this->priority,
            'assignee_id' => $this->assigneeId,
            'due_at'      => $this->dueAt,
        ], fn (mixed $v): bool => $v !== null);
    }

    public function withPriority(TicketPriority $priority): self
    {
        $clone = clone $this;
        $clone->priority = $priority;

        return $clone;
    }
}

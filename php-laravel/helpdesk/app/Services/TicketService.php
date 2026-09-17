<?php
// app/Services/TicketService.php
declare(strict_types=1);

namespace App\Services;

use App\DTO\TicketData;
use App\Enums\TicketStatus;
use App\Events\TicketAssigned;
use App\Events\TicketClosed;
use App\Events\TicketCreated;
use App\Exceptions\AgentOverloadedException;
use App\Exceptions\InvalidStatusTransitionException;
use App\Exceptions\TicketAlreadyAssignedException;
use App\Exceptions\TicketLimitExceededException;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

final readonly class TicketService
{
    public function __construct(
        private TagResolver $tags,
    ) {
    }

    public function create(User $author, TicketData $data): Ticket
    {
        $this->assertUnderLimit($author);

        $ticket = DB::transaction(function () use ($author, $data): Ticket {
            $ticket = $author->tickets()->create($data->toAttributes());

            if ($data->tags !== []) {
                $ticket->tags()->sync($this->tags->idsBySlugs($data->tags));
            }

            $ticket->comments()->create([
                'author_id' => $author->id,
                'is_system' => true,
                'body'      => 'Заявка создана.',
            ]);

            return $ticket;
        }, attempts: 3);

        TicketCreated::dispatch($ticket);

        return $ticket->load('author', 'tags');
    }

    public function close(Ticket $ticket, User $actor, ?string $resolution = null): Ticket
    {
        $this->assertCanTransition($ticket, TicketStatus::Closed);

        $closed = DB::transaction(function () use ($ticket, $actor, $resolution): Ticket {
            $ticket->update([
                'status'      => TicketStatus::Closed,
                'resolved_at' => now(),
                'resolution'  => $resolution,
            ]);

            $ticket->comments()->create([
                'author_id' => $actor->id,
                'is_system' => true,
                'body'      => 'Заявка закрыта.' . ($resolution !== null ? " {$resolution}" : ''),
            ]);

            return $ticket->refresh();
        }, attempts: 3);

        TicketClosed::dispatch($closed, $actor);

        return $closed;
    }

    public function assign(Ticket $ticket, User $agent, User $actor): Ticket
    {
        $assigned = DB::transaction(function () use ($ticket, $agent): Ticket {
            $profile = $agent->agentProfile()->lockForUpdate()->firstOrFail();

            $current = Ticket::query()->where('assignee_id', $agent->id)->open()->count();

            if ($current >= $profile->max_tickets) {
                throw new AgentOverloadedException($agent->id, $current, $profile->max_tickets);
            }

            $updated = Ticket::query()
                ->whereKey($ticket->id)
                ->whereNull('assignee_id')
                ->update(['assignee_id' => $agent->id, 'updated_at' => now()]);

            if ($updated === 0) {
                throw new TicketAlreadyAssignedException($ticket->id);
            }

            return $ticket->refresh();
        }, attempts: 3);

        TicketAssigned::dispatch($assigned, $agent, $actor);

        return $assigned;
    }

    private function assertUnderLimit(User $author): void
    {
        $limit = config('helpdesk.limits.open_tickets_per_user');
        $current = $author->tickets()->open()->count();

        if ($current >= $limit) {
            throw new TicketLimitExceededException($limit, $current);
        }
    }

    private function assertCanTransition(Ticket $ticket, TicketStatus $next): void
    {
        if (! $ticket->status->canTransitionTo($next)) {
            throw new InvalidStatusTransitionException($ticket->status, $next);
        }
    }
}

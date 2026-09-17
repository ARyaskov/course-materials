<?php
// app/Actions/Ticket/CloseTicket.php
declare(strict_types=1);

namespace App\Actions\Ticket;

use App\Enums\TicketStatus;
use App\Events\TicketClosed;
use App\Exceptions\InvalidStatusTransitionException;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

final readonly class CloseTicket
{
    public function __construct(private CommentWriter $comments)
    {
    }

    public function __invoke(Ticket $ticket, User $actor, ?string $resolution = null): Ticket
    {
        if (! $ticket->status->canTransitionTo(TicketStatus::Closed)) {
            throw new InvalidStatusTransitionException($ticket->status, TicketStatus::Closed);
        }

        $closed = DB::transaction(function () use ($ticket, $actor, $resolution): Ticket {
            $ticket->update([
                'status'      => TicketStatus::Closed,
                'resolved_at' => now(),
                'resolution'  => $resolution,
            ]);

            $this->comments->system($ticket, $actor, 'Заявка закрыта.');

            return $ticket->refresh();
        }, attempts: 3);

        TicketClosed::dispatch($closed, $actor);

        return $closed;
    }
}

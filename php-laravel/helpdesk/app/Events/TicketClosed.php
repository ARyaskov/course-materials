<?php
// app/Events/TicketClosed.php
declare(strict_types=1);

namespace App\Events;

use App\Models\Ticket;
use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;

final readonly class TicketClosed
{
    use Dispatchable;

    public function __construct(
        public Ticket $ticket,
        public User $actor,
    ) {
    }
}

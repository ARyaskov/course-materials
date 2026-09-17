<?php

declare(strict_types=1);

namespace App\Events;

use App\Models\Ticket;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

final class TicketCreated
{
    use Dispatchable;
    use SerializesModels;

    public function __construct(public readonly Ticket $ticket)
    {
    }
}

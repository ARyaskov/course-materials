<?php
// app/Http/Controllers/Ticket/CloseTicketController.php
declare(strict_types=1);

namespace App\Http\Controllers\Ticket;

use App\Http\Controllers\Controller;
use App\Http\Requests\CloseTicketRequest;
use App\Http\Resources\TicketResource;
use App\Models\Ticket;
use App\Services\TicketService;

final class CloseTicketController extends Controller
{
    public function __construct(private readonly TicketService $tickets)
    {
    }

    public function __invoke(CloseTicketRequest $request, Ticket $ticket): TicketResource
    {
        return TicketResource::make(
            $this->tickets->close($ticket, $request->user(), $request->resolution())
        );
    }
}

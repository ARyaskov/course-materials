<?php
// app/Http/Responses/TicketCreated.php
declare(strict_types=1);

namespace App\Http\Responses;

use App\Http\Resources\TicketResource;
use App\Models\Ticket;
use Illuminate\Contracts\Support\Responsable;
use Illuminate\Http\JsonResponse;

final readonly class TicketCreated implements Responsable
{
    public function __construct(private Ticket $ticket)
    {
    }

    public function toResponse($request): JsonResponse
    {
        return TicketResource::make($this->ticket->load('author'))
            ->response($request)
            ->setStatusCode(201)
            ->header('Location', route('tickets.show', $this->ticket));
    }
}

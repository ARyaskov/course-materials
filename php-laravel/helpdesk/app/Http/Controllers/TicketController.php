<?php
// app/Http/Controllers/TicketController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use App\Http\Requests\StoreTicketRequest;
use App\Http\Requests\TicketIndexRequest;
use App\Http\Requests\UpdateTicketRequest;
use App\Http\Resources\TicketCollection;
use App\Http\Resources\TicketResource;
use App\Models\Ticket;
use App\Queries\TicketQuery;
use App\Services\TicketService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;

final class TicketController extends Controller
{
    public function __construct(private readonly TicketService $tickets)
    {
    }

    public function index(TicketIndexRequest $request): TicketCollection
    {
        $filters = $request->toFilters();

        $query = new TicketQuery(
            filters: $filters,
            user: $request->user(),
            includes: $request->includes(),
            sort: $request->sort(),
        );

        $page = $request->filled('cursor')
            ? $query->cursorPaginate($request->perPage())
            : $query->paginate($request->perPage());

        return new TicketCollection($page, $query->countsByStatus(), $filters);
    }

    public function store(StoreTicketRequest $request): JsonResponse
    {
        $ticket = $this->tickets->create($request->user(), $request->toData());

        return $this->created(
            TicketResource::make($ticket->load('author', 'tags')),
            route('tickets.show', $ticket),
        );
    }

    public function show(Ticket $ticket): TicketResource
    {
        $this->authorize('view', $ticket);

        return TicketResource::make($ticket->load([
            'author:id,name,email,role',
            'assignee:id,name,role',
            'tags',
            'comments' => fn ($q) => $q->with('author:id,name,role', 'attachments')->oldest(),
            'attachments',
        ]));
    }

    public function update(UpdateTicketRequest $request, Ticket $ticket): TicketResource
    {
        return TicketResource::make(
            $this->tickets->update($ticket, $request->toData())->load('author', 'tags')
        );
    }

    public function destroy(Ticket $ticket): Response
    {
        $this->authorize('delete', $ticket);
        $this->tickets->delete($ticket);

        return $this->noContent();
    }
}

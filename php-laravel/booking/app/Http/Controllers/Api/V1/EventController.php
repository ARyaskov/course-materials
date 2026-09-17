<?php
// app/Http/Controllers/Api/V1/EventController.php
declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\IndexEventRequest;
use App\Http\Requests\StoreEventRequest;
use App\Http\Requests\UpdateEventRequest;
use App\Http\Resources\EventResource;
use App\Models\Event;
use App\Queries\EventCatalogQuery;
use App\Services\EventService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Http\Response;
use Illuminate\Routing\Controllers\HasMiddleware;
use Illuminate\Routing\Controllers\Middleware;

final class EventController extends Controller implements HasMiddleware
{
    public function __construct(private readonly EventService $events)
    {
    }

    public static function middleware(): array
    {
        return [
            new Middleware('throttle:60,1', only: ['index', 'show']),
            new Middleware('throttle:20,1', only: ['store', 'update', 'destroy']),
        ];
    }

    public function index(IndexEventRequest $request): AnonymousResourceCollection
    {
        return EventResource::collection(
            EventCatalogQuery::fromRequest($request->filters())->paginate($request->perPage())
        );
    }

    public function show(Event $event): EventResource
    {
        abort_unless($event->status->isVisibleInCatalog(), Response::HTTP_NOT_FOUND);

        return new EventResource(
            $event->load('organizer:id,name')->loadSum(
                ['bookings as occupied_seats' => fn ($q) => $q->active()],
                'seats',
            )
        );
    }

    public function store(StoreEventRequest $request): JsonResponse
    {
        $event = $this->events->create($request->user(), $request->validated());

        return (new EventResource($event->load('organizer:id,name')))
            ->response()
            ->setStatusCode(Response::HTTP_CREATED)
            ->header('Location', route('events.show', $event));
    }

    public function update(UpdateEventRequest $request, Event $event): EventResource
    {
        return new EventResource($this->events->update($event, $request->validated()));
    }

    public function publish(Event $event): EventResource
    {
        $this->authorize('update', $event);

        return new EventResource($this->events->publish($event));
    }

    public function destroy(Event $event): Response
    {
        $this->authorize('delete', $event);

        $this->events->archive($event);

        return response()->noContent();
    }
}

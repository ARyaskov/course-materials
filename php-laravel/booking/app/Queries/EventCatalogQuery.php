<?php
// app/Queries/EventCatalogQuery.php
declare(strict_types=1);

namespace App\Queries;

use App\Models\Event;
use Illuminate\Contracts\Pagination\CursorPaginator;
use Illuminate\Database\Eloquent\Builder;

final readonly class EventCatalogQuery
{
    private const SORTS = [
        'starts_at' => ['starts_at', 'asc'],
        '-starts_at' => ['starts_at', 'desc'],
        'price' => ['price', 'asc'],
        '-price' => ['price', 'desc'],
        '-created_at' => ['created_at', 'desc'],
    ];

    public function __construct(
        private ?string $search = null,
        private ?string $venue = null,
        private ?int $priceMax = null,
        private ?string $from = null,
        private ?string $to = null,
        private bool $onlyAvailable = false,
        private string $sort = 'starts_at',
    ) {
    }

    public static function fromRequest(array $filters): self
    {
        return new self(
            search: $filters['search'] ?? null,
            venue: $filters['venue'] ?? null,
            priceMax: isset($filters['price_max']) ? (int) $filters['price_max'] : null,
            from: $filters['from'] ?? null,
            to: $filters['to'] ?? null,
            onlyAvailable: (bool) ($filters['available'] ?? false),
            sort: $filters['sort'] ?? 'starts_at',
        );
    }

    public function paginate(int $perPage): CursorPaginator
    {
        return $this->builder()->cursorPaginate($perPage)->withQueryString();
    }

    private function builder(): Builder
    {
        return Event::query()
            ->published()
            ->upcoming()
            ->with('organizer:id,name')
            ->withSum(
                ['bookings as occupied_seats' => fn (Builder $q) => $q->active()],
                'seats',
            )
            ->when($this->search, fn (Builder $q, string $term) => $q->where(
                fn (Builder $inner) => $inner
                    ->where('title', 'ilike', "%{$term}%")
                    ->orWhere('description', 'ilike', "%{$term}%")
            ))
            ->when($this->venue, fn (Builder $q, string $venue) => $q->where('venue', 'ilike', "%{$venue}%"))
            ->when($this->priceMax !== null, fn (Builder $q) => $q->where('price', '<=', $this->priceMax))
            ->when($this->from, fn (Builder $q, string $from) => $q->where('starts_at', '>=', $from))
            ->when($this->to, fn (Builder $q, string $to) => $q->where('starts_at', '<=', $to))
            ->when($this->onlyAvailable, fn (Builder $q) => $q->whereRaw('
                capacity > COALESCE((
                    SELECT SUM(seats) FROM bookings
                    WHERE bookings.event_id = events.id
                      AND bookings.status IN (?, ?)
                ), 0)
            ', ['held', 'confirmed']))
            ->orderBy(...self::SORTS[$this->sort] ?? self::SORTS['starts_at'])
            ->orderBy('id');
    }
}

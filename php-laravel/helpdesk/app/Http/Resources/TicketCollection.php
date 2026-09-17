<?php
// app/Http/Resources/TicketCollection.php
declare(strict_types=1);

namespace App\Http\Resources;

use App\DTO\TicketFilters;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\ResourceCollection;

final class TicketCollection extends ResourceCollection
{
    public $collects = TicketListResource::class;

    /** @param  array<string, int>  $counts */
    public function __construct(
        $resource,
        private readonly array $counts = [],
        private readonly ?TicketFilters $filters = null,
    ) {
        parent::__construct($resource);
    }

    /** Элементы отдаёт родитель; здесь — только дополнительные метаданные. */
    public function with(Request $request): array
    {
        return [
            'meta' => [
                'counts'  => array_map(
                    fn (TicketStatus $s): int => $this->counts[$s->value] ?? 0,
                    array_combine(
                        array_column(TicketStatus::cases(), 'value'),
                        TicketStatus::cases(),
                    ),
                ),
                'filters'   => $this->filters?->toArray() ?? [],
                'available' => [
                    'statuses'   => array_column(TicketStatus::cases(), 'value'),
                    'priorities' => array_column(TicketPriority::cases(), 'value'),
                    'sorts'      => ['created_at', '-created_at', 'priority', '-priority', 'subject'],
                ],
            ],
        ];
    }
}

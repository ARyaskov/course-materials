<?php
// app/Http/Resources/TicketStatsResource.php
declare(strict_types=1);

namespace App\Http\Resources;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

final class TicketStatsResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'period' => [
                'from' => $this->resource['from']->toDateString(),
                'to'   => $this->resource['to']->toDateString(),
            ],
            'totals' => [
                'created'  => (int) $this->resource['created'],
                'closed'   => (int) $this->resource['closed'],
                'overdue'  => (int) $this->resource['overdue'],
            ],
            'avg_resolution_hours' => round((float) $this->resource['avg_hours'], 1),
            'by_priority' => collect($this->resource['by_priority'])
                ->map(fn (int $count, string $priority): array => [
                    'priority' => $priority,
                    'count'    => $count,
                ])
                ->values(),
        ];
    }
}

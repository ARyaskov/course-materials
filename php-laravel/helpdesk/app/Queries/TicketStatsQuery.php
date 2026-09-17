<?php
// app/Queries/TicketStatsQuery.php
declare(strict_types=1);

namespace App\Queries;

use App\DTO\TicketStats;
use App\Models\User;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

final readonly class TicketStatsQuery
{
    private const int TTL = 300;

    public function forUser(User $user): TicketStats
    {
        return Cache::remember(
            "stats:user:{$user->id}",
            self::TTL,
            fn (): TicketStats => $this->build($user),
        );
    }

    private function build(User $user): TicketStats
    {
        $row = DB::table('tickets')
            ->when(! $user->isAgent(), fn ($q) => $q->where('author_id', $user->id))
            ->whereNull('deleted_at')
            ->selectRaw("
                count(*) as total,
                count(*) filter (where status = 'closed') as closed,
                count(*) filter (where resolved_at is null
                    and created_at + (sla_hours || ' hours')::interval < now()) as overdue,
                avg(extract(epoch from (resolved_at - created_at)) / 3600) as avg_hours
            ")
            ->first();

        return new TicketStats(
            total: (int) $row->total,
            closed: (int) $row->closed,
            overdue: (int) $row->overdue,
            avgResolutionHours: round((float) ($row->avg_hours ?? 0), 1),
        );
    }
}

<?php
// app/Queries/AgentPerformanceQuery.php
declare(strict_types=1);

namespace App\Queries;

use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

final readonly class AgentPerformanceQuery
{
    /** @return Collection<int, object> */
    public function forPeriod(\DateTimeInterface $from, \DateTimeInterface $to): Collection
    {
        return DB::table('users')
            ->leftJoin('tickets', function ($join) use ($from, $to): void {
                $join->on('tickets.assignee_id', '=', 'users.id')
                    ->whereNull('tickets.deleted_at')
                    ->whereBetween('tickets.created_at', [$from, $to]);
            })
            ->where('users.role', 'agent')
            ->groupBy('users.id', 'users.name')
            ->select([
                'users.id',
                'users.name',
                DB::raw('count(tickets.id) as total'),
                DB::raw("count(*) filter (where tickets.status = 'closed') as closed"),
                DB::raw("count(*) filter (where tickets.status != 'closed') as in_progress"),
                DB::raw('round(avg(extract(epoch from (tickets.resolved_at - tickets.created_at)) / 3600)::numeric, 1) as avg_hours'),
                DB::raw("count(*) filter (where tickets.priority in ('high','critical')) as urgent"),
            ])
            ->orderByDesc('total')
            ->get();
    }
}

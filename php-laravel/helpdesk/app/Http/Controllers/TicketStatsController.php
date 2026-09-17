<?php
// app/Http/Controllers/TicketStatsController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\Ticket;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;

final class TicketStatsController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $stats = Cache::remember("stats:{$request->user()->id}", 300, function () use ($request): array {
            $byStatus = Ticket::query()
                ->when(! $request->user()->isAgent(), fn ($q) => $q->where('author_id', $request->user()->id))
                ->groupBy('status')
                ->selectRaw('status, count(*) as total')
                ->pluck('total', 'status');

            $overdue = Ticket::query()
                ->whereNull('resolved_at')
                ->whereRaw("created_at + (sla_hours || ' hours')::interval < now()")
                ->count();

            $unanswered = Ticket::query()
                ->whereNot('status', 'closed')
                ->whereDoesntHave('comments', fn ($q) => $q->whereHas(
                    'author',
                    fn ($a) => $a->where('role', 'agent'),
                ))
                ->count();

            return [
                'by_status'  => $byStatus,
                'overdue'    => $overdue,
                'unanswered' => $unanswered,
            ];
        });

        return response()->json(['data' => $stats]);
    }
}

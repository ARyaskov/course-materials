<?php
// app/Services/TicketAssignmentService.php
declare(strict_types=1);

namespace App\Services;

use App\Exceptions\AgentOverloadedException;
use App\Exceptions\TicketAlreadyAssignedException;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

final readonly class TicketAssignmentService
{
    public function assign(Ticket $ticket, User $agent, User $actor): Ticket
    {
        return DB::transaction(function () use ($ticket, $agent, $actor): Ticket {
            // блокируем профиль исполнителя — проверка лимита должна быть последовательной
            $profile = $agent->agentProfile()->lockForUpdate()->firstOrFail();

            $current = Ticket::query()
                ->where('assignee_id', $agent->id)
                ->open()
                ->count();

            if ($current >= $profile->max_tickets) {
                throw new AgentOverloadedException($agent->id, $current, $profile->max_tickets);
            }

            // атомарно: назначаем только незанятую заявку
            $updated = Ticket::query()
                ->whereKey($ticket->id)
                ->whereNull('assignee_id')
                ->update([
                    'assignee_id' => $agent->id,
                    'version'     => DB::raw('version + 1'),
                    'updated_at'  => now(),
                ]);

            if ($updated === 0) {
                throw new TicketAlreadyAssignedException($ticket->id);
            }

            $ticket->refresh();

            $ticket->comments()->create([
                'author_id' => $actor->id,
                'is_system' => true,
                'body'      => "Заявка назначена на {$agent->name}.",
            ]);

            return $ticket->load('assignee', 'author');
        }, attempts: 3);
    }
}

<?php
// app/Support/TicketCache.php
declare(strict_types=1);

namespace App\Support;

use App\Models\Ticket;
use Illuminate\Support\Facades\Cache;

final readonly class TicketCache
{
    private const string VERSION = 'v2';

    public function statsKey(int $userId): string
    {
        return sprintf('stats:%s:user:%d', self::VERSION, $userId);
    }

    public function ticketKey(int $ticketId): string
    {
        return sprintf('ticket:%s:%d', self::VERSION, $ticketId);
    }

    public function forgetForTicket(Ticket $ticket): void
    {
        Cache::forget($this->ticketKey($ticket->id));

        $this->forgetForUser($ticket->author_id);

        if ($ticket->assignee_id !== null) {
            $this->forgetForUser($ticket->assignee_id);
        }

        Cache::forget(sprintf('stats:%s:global', self::VERSION));

        // списки инвалидируем меткой поколения — см. ниже
        $this->bumpListGeneration();
    }

    public function forgetForUser(int $userId): void
    {
        Cache::forget($this->statsKey($userId));
    }

    public function listKey(int $userId, string $filtersHash): string
    {
        $generation = Cache::get('tickets:list:generation', 1);

        return sprintf('tickets:list:%s:g%d:user:%d:%s', self::VERSION, $generation, $userId, $filtersHash);
    }

    public function bumpListGeneration(): void
    {
        Cache::increment('tickets:list:generation');
    }
}

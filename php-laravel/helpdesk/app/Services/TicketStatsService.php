<?php
// app/Services/TicketStatsService.php
declare(strict_types=1);

namespace App\Services;

use App\Models\Ticket;
use App\Support\Concerns\Cacheable;

final class TicketStatsService
{
    use Cacheable;

    public function __construct(private readonly int $userId)
    {
    }

    public function summary(): array
    {
        return $this->remember(fn (): array => [
            'open'   => Ticket::query()->where('assignee_id', $this->userId)->open()->count(),
            'closed' => Ticket::query()->where('assignee_id', $this->userId)->closed()->count(),
        ]);
    }

    protected function cacheKey(): string
    {
        return "stats:user:{$this->userId}";
    }

    protected function cacheTtl(): int
    {
        return 300;
    }
}

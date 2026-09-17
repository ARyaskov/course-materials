<?php
// app/Jobs/ProcessTicket.php
declare(strict_types=1);

namespace App\Jobs;

use App\Support\TenantContext;

final class ProcessTicket implements ShouldQueue
{
    public function __construct(
        public readonly int $tenantId,
        public readonly int $ticketId,
    ) {
    }

    public function handle(): void
    {
        TenantContext::set($this->tenantId);

        try {
            // ... обработка
        } finally {
            TenantContext::forget();
        }
    }
}

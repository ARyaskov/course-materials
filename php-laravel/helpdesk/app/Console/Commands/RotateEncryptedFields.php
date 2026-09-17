<?php
// app/Console/Commands/RotateEncryptedFields.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\Ticket;
use Illuminate\Console\Command;

final class RotateEncryptedFields extends Command
{
    protected $signature = 'app:rotate-encrypted {--chunk=500}';

    protected $description = 'Перешифровывает поля новым ключом';

    public function handle(): int
    {
        $total = Ticket::query()->whereNotNull('internal_note')->count();
        $bar = $this->output->createProgressBar($total);

        Ticket::query()
            ->whereNotNull('internal_note')
            ->lazyById((int) $this->option('chunk'))
            ->each(function (Ticket $ticket) use ($bar): void {
                // чтение расшифрует старым ключом, запись зашифрует новым
                $ticket->updateQuietly(['internal_note' => $ticket->internal_note]);
                $bar->advance();
            });

        $bar->finish();
        $this->newLine(2);
        $this->info('Готово. Уберите APP_PREVIOUS_KEYS из окружения.');

        return self::SUCCESS;
    }
}

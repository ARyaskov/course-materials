<?php
// app/Console/Commands/WarmCache.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\Tag;
use App\Models\User;
use App\Queries\TicketStatsQuery;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Cache;

final class WarmCache extends Command
{
    protected $signature = 'cache:warm';

    protected $description = 'Заполняет кэш часто используемыми данными';

    public function handle(TicketStatsQuery $stats): int
    {
        Cache::forever('tags:all', Tag::query()->pluck('name', 'slug')->all());
        $this->info('Справочник меток прогрет.');

        $agents = User::query()->where('role', 'agent')->get();

        $bar = $this->output->createProgressBar($agents->count());

        foreach ($agents as $agent) {
            $stats->forUser($agent);
            $bar->advance();
        }

        $bar->finish();
        $this->newLine(2);
        $this->info("Статистика прогрета для {$agents->count()} сотрудников.");

        return self::SUCCESS;
    }
}

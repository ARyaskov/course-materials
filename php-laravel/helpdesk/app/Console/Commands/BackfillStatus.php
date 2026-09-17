<?php
// app/Console/Commands/BackfillStatus.php
declare(strict_types=1);

namespace App\Console\Commands;

use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Number;

final class BackfillStatus extends Command
{
    protected $signature = 'app:backfill-status';
    protected $description = 'Прогресс переноса данных';

    public function handle(): int
    {
        $total = DB::table('tickets')->count();
        $done = DB::table('tickets')->whereNotNull('subject')->count();

        $this->table(
            ['Всего', 'Перенесено', 'Осталось', 'Доля'],
            [[
                Number::format($total, locale: 'ru'),
                Number::format($done, locale: 'ru'),
                Number::format($total - $done, locale: 'ru'),
                Number::percentage($total > 0 ? $done / $total * 100 : 100, precision: 1),
            ]],
        );

        return self::SUCCESS;
    }
}

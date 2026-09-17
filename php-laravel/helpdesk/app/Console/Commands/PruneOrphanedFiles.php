<?php
// app/Console/Commands/PruneOrphanedFiles.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Models\Attachment;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Storage;

final class PruneOrphanedFiles extends Command
{
    protected $signature = 'files:prune {--disk=private} {--dry-run}';

    protected $description = 'Удаляет файлы, на которые нет ссылок в базе';

    public function handle(): int
    {
        $disk = Storage::disk($this->option('disk'));
        $known = Attachment::query()->pluck('path')->flip();

        $orphaned = [];
        $freed = 0;

        foreach ($disk->allFiles('tickets') as $file) {
            if ($known->has($file)) {
                continue;
            }

            // не трогаем свежие — файл мог быть загружен секунду назад
            if ($disk->lastModified($file) > now()->subDay()->timestamp) {
                continue;
            }

            $orphaned[] = $file;
            $freed += $disk->size($file);
        }

        if ($orphaned === []) {
            $this->info('Файлов без ссылок нет.');

            return self::SUCCESS;
        }

        $this->warn(sprintf(
            'Найдено файлов без ссылок: %d, объём %s',
            count($orphaned),
            \Illuminate\Support\Number::fileSize($freed),
        ));

        if ($this->option('dry-run')) {
            $this->table(['путь'], array_map(fn (string $p): array => [$p], array_slice($orphaned, 0, 20)));

            return self::SUCCESS;
        }

        $disk->delete($orphaned);
        $this->info('Удалено.');

        return self::SUCCESS;
    }
}

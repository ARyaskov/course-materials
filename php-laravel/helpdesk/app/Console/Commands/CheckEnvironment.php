<?php
// app/Console/Commands/CheckEnvironment.php
declare(strict_types=1);

namespace App\Console\Commands;

use Illuminate\Console\Command;

final class CheckEnvironment extends Command
{
    protected $signature = 'app:check-env';

    protected $description = 'Проверяет готовность окружения';

    public function handle(): int
    {
        $checks = [
            'APP_KEY задан'          => filled(config('app.key')),
            'APP_DEBUG выключен'     => config('app.debug') === false,
            'APP_URL по HTTPS'       => str_starts_with((string) config('app.url'), 'https://'),
            'Часовой пояс UTC'       => config('app.timezone') === 'UTC',
            'Кэш не файловый'        => config('cache.default') !== 'file',
            'Очередь не sync'        => config('queue.default') !== 'sync',
            'База доступна'          => $this->canConnect('database'),
            'Redis доступен'         => $this->canConnect('redis'),
            'Пароль базы задан'      => filled(config('database.connections.pgsql.password')),
            'Ключи интеграций'       => filled(config('services.crm.key')) && filled(config('services.directory.key')),
            'storage доступен'       => is_writable(storage_path('logs')),
        ];

        $failed = false;

        foreach ($checks as $name => $ok) {
            $this->line(sprintf('%s %s', $ok ? '<fg=green>✓</>' : '<fg=red>✗</>', $name));
            $failed = $failed || ! $ok;
        }

        return $failed ? self::FAILURE : self::SUCCESS;
    }

    private function canConnect(string $service): bool
    {
        try {
            match ($service) {
                'database' => \Illuminate\Support\Facades\DB::connection()->getPdo(),
                'redis'    => \Illuminate\Support\Facades\Redis::connection()->ping(),
            };

            return true;
        } catch (\Throwable) {
            return false;
        }
    }
}

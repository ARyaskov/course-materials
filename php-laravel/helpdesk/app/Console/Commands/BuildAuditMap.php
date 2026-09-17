<?php
// app/Console/Commands/BuildAuditMap.php
declare(strict_types=1);

namespace App\Console\Commands;

use App\Attributes\AuditAction;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Route;
use ReflectionMethod;

final class BuildAuditMap extends Command
{
    protected $signature = 'audit:map';

    protected $description = 'Собирает карту действий, помеченных AuditAction';

    public function handle(): int
    {
        $map = [];

        foreach (Route::getRoutes() as $route) {
            $action = $route->getActionName();

            if (! str_contains($action, '@')) {
                continue;
            }

            [$class, $method] = explode('@', $action);
            $attributes = new ReflectionMethod($class, $method)->getAttributes(AuditAction::class);

            if ($attributes !== []) {
                $map[$route->getName()] = $attributes[0]->newInstance()->action;
            }
        }

        file_put_contents(
            storage_path('app/audit-map.php'),
            '<?php return ' . var_export($map, true) . ';',
        );

        $this->info('Записано действий: ' . count($map));

        return self::SUCCESS;
    }
}

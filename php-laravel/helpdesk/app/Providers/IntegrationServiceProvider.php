<?php
// app/Providers/IntegrationServiceProvider.php
declare(strict_types=1);

namespace App\Providers;

use App\Contracts\AgentDirectory;
use App\Services\Directory\HttpAgentDirectory;
use Illuminate\Contracts\Foundation\Application;
use Illuminate\Support\ServiceProvider;

final class IntegrationServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->app->singleton(AgentDirectory::class, fn (Application $app) => new HttpAgentDirectory(
            baseUrl: config('services.directory.url'),
            apiKey: config('services.directory.key'),
            timeout: (int) config('services.directory.timeout', 3),
            cacheTtl: (int) config('services.directory.cache_ttl', 600),
        ));
    }
}

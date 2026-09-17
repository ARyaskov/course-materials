<?php
// app/Providers/SearchServiceProvider.php
declare(strict_types=1);

namespace App\Providers;

use App\Contracts\SearchIndex;
use App\Services\Search\RedisSearchIndex;
use Illuminate\Contracts\Support\DeferrableProvider;
use Illuminate\Support\ServiceProvider;

final class SearchServiceProvider extends ServiceProvider implements DeferrableProvider
{
    public function register(): void
    {
        $this->app->singleton(SearchIndex::class, fn ($app) => new RedisSearchIndex(
            $app->make(\Illuminate\Redis\RedisManager::class),
            config('helpdesk.search.prefix'),
        ));
    }

    /** @return list<string> */
    public function provides(): array
    {
        return [SearchIndex::class];
    }
}

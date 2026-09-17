<?php

declare(strict_types=1);

namespace App\Providers;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\ServiceProvider;
use Illuminate\Validation\Rules\Password;

final class AppServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // ленивая загрузка, доступ к отсутствующим атрибутам и лишний fill — ошибки
        Model::shouldBeStrict(! $this->app->isProduction());

        Model::handleLazyLoadingViolationUsing(
            fn (Model $model, string $relation) => Log::warning('eloquent.lazy_loading', [
                'model' => $model::class,
                'relation' => $relation,
            ])
        );

        DB::whenQueryingForLongerThan(500, fn ($connection) => Log::warning('db.slow_request', [
            'total_ms' => $connection->totalQueryDuration(),
        ]));

        Password::defaults(fn () => $this->app->isProduction()
            ? Password::min(12)->max(64)->uncompromised()->letters()->numbers()
            : Password::min(8));
    }
}

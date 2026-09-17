<?php

declare(strict_types=1);

namespace App\Providers;

use App\Models\Attachment;
use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\Relation;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\URL;
use Illuminate\Support\ServiceProvider;
use Illuminate\Validation\Rules\Password;
use Illuminate\Queue\Events\JobFailed;
use Illuminate\Queue\Events\JobProcessed;

final class AppServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        //
    }

    public function boot(): void
    {
        $this->configureModels();
        $this->configureRequests();
        $this->configureRateLimiting();
        $this->configureQueue();
        $this->configureHttpClient();
    }

    /** Строгий режим Eloquent — включён с первого дня проекта. */
    private function configureModels(): void
    {
        // ленивая загрузка, лишние атрибуты и обращение к отсутствующим — ошибки
        Model::shouldBeStrict(! $this->app->isProduction());

        // в рабочей среде не падаем, но фиксируем
        Model::handleLazyLoadingViolationUsing(
            fn (Model $model, string $relation) => Log::warning('eloquent.lazy_loading', [
                'model' => $model::class,
                'relation' => $relation,
            ])
        );

        // короткие имена в полиморфных связях вместо полных имён классов
        Relation::enforceMorphMap([
            'ticket' => Ticket::class,
            'comment' => Comment::class,
            'user' => User::class,
            'attachment' => Attachment::class,
        ]);

        DB::whenQueryingForLongerThan(500, fn ($connection) => Log::warning('db.slow_request', [
            'total_ms' => $connection->totalQueryDuration(),
        ]));
    }

    private function configureRequests(): void
    {
        // конверт формируют ресурсы: TicketCollection сам возвращает data/meta,
        // одиночные ресурсы оборачиваются фреймворком в data
        JsonResource::wrap('data');

        // https за прокси: ссылки в ответах должны быть https
        if ($this->app->isProduction()) {
            URL::forceScheme('https');
        }

        Password::defaults(fn () => $this->app->isProduction()
            ? Password::min(12)->max(64)->letters()->mixedCase()->numbers()->uncompromised()
            : Password::min(12)->letters()->numbers());
    }

    private function configureRateLimiting(): void
    {
        RateLimiter::for('api', fn (Request $request) => Limit::perMinute(60)
            ->by($request->user()?->id ?: $request->ip())
            ->response(fn (Request $request, array $headers) => response()->json([
                'message' => 'Слишком много запросов. Повторите позже.',
                'code' => 'too_many_requests',
                'retry_after' => $headers['Retry-After'] ?? 60,
            ], 429, $headers)));

        RateLimiter::for('login', fn (Request $request) => Limit::perMinute(5)
            ->by($request->string('email')->lower() . '|' . $request->ip()));

        RateLimiter::for('exports', fn (Request $request) => Limit::perHour(10)
            ->by($request->user()?->id ?: $request->ip()));

        // запись дороже чтения — отдельный, более строгий лимит
        RateLimiter::for('writes', fn (Request $request) => Limit::perMinute(20)
            ->by($request->user()?->id ?: $request->ip()));

        RateLimiter::for('uploads', fn (Request $request) => Limit::perMinute(10)
            ->by($request->user()?->id ?: $request->ip()));

        RateLimiter::for('reports', fn (Request $request) => Limit::perHour(10)
            ->by($request->user()?->id ?: $request->ip()));

        RateLimiter::for('register', fn (Request $request) => Limit::perMinute(10)->by($request->ip()));

        RateLimiter::for('password-reset', fn (Request $request) => Limit::perMinute(3)
            ->by($request->string('email')->lower() . '|' . $request->ip()));
    }

    private function configureQueue(): void
    {
        Queue::failing(fn (JobFailed $event) => Log::error('queue.job_failed', [
            'connection' => $event->connectionName,
            'job' => $event->job->resolveName(),
            'exception' => $event->exception->getMessage(),
        ]));

        Queue::after(fn (JobProcessed $event) => Log::debug('queue.job_processed', [
            'job' => $event->job->resolveName(),
        ]));
    }

    private function configureHttpClient(): void
    {
        Http::globalOptions([
            'connect_timeout' => 3,
            'timeout' => 10,
        ]);

        Http::macro('crm', fn () => Http::baseUrl(config('services.crm.url'))
            ->withToken(config('services.crm.token'))
            ->retry(3, 200, throw: false)
            ->timeout(10));
    }
}

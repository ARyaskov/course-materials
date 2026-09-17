<?php

declare(strict_types=1);

use App\Exceptions\ApiExceptionRenderer;
use App\Exceptions\DomainException;
use App\Http\Middleware\ApiHeaders;
use App\Http\Middleware\EnsureIdempotency;
use App\Http\Middleware\EnsureUserIsAgent;
use App\Http\Middleware\RecordAudit;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Context;
use Illuminate\Support\Lottery;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api.php',
        commands: __DIR__ . '/../routes/console.php',
        health: '/up',
        apiPrefix: 'api/v1',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // самый внешний слой группы api — первый на входе, последний на выходе
        $middleware->api(prepend: [ApiHeaders::class]);
        $middleware->api(append: [RecordAudit::class]);

        $middleware->throttleApi('60,1');

        $middleware->alias([
            'agent' => EnsureUserIsAgent::class,
            'idempotent' => EnsureIdempotency::class,
        ]);

        $middleware->priority([
            ApiHeaders::class,
            \Illuminate\Auth\Middleware\Authenticate::class,
            \Illuminate\Routing\Middleware\ThrottleRequests::class,
            EnsureUserIsAgent::class,
        ]);

        $middleware->trustProxies(
            at: ['10.0.0.0/8', '172.16.0.0/12'],
            headers: Request::HEADER_X_FORWARDED_FOR
                | Request::HEADER_X_FORWARDED_HOST
                | Request::HEADER_X_FORWARDED_PORT
                | Request::HEADER_X_FORWARDED_PROTO,
        );

        $middleware->preventRequestsDuringMaintenance(except: ['up', 'api/v1/health']);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // как превратить исключение в ответ API
        $exceptions->render(fn (\Throwable $e, Request $request) => $request->is('api/*')
            ? app(ApiExceptionRenderer::class)($e, $request)
            : null);

        // ожидаемые ошибки не засоряют лог и систему оповещений
        $exceptions->dontReport([
            DomainException::class,
            \Illuminate\Http\Client\ConnectionException::class,
        ]);

        $exceptions->dontFlash(['password', 'password_confirmation', 'current_password', 'token', 'secret']);

        // общий контекст всех записей об ошибках
        $exceptions->context(fn (): array => [
            'request_id' => Context::get('request_id'),
            'user_id' => auth()->id(),
        ]);

        // ограничение частоты записей об одной и той же ошибке
        $exceptions->throttle(fn (\Throwable $e) => match (true) {
            $e instanceof \Illuminate\Http\Client\ConnectionException => Lottery::odds(1, 100),
            default => null,
        });
    })
    ->create();

<?php
// app/Http/Middleware/RecordApiMetrics.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class RecordApiMetrics
{
    public function handle(Request $request, Closure $next): Response
    {
        return $next($request);
    }

    public function terminate(Request $request, Response $response): void
    {
        // клиент ответ уже получил — здесь можно не спешить
        logger()->info('api', [
            'route'  => $request->route()?->getName(),
            'status' => $response->getStatusCode(),
            'ms'     => round((microtime(true) - LARAVEL_START) * 1000, 1),
        ]);
    }
}

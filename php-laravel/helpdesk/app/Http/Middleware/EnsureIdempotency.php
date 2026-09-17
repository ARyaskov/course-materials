<?php
// app/Http/Middleware/EnsureIdempotency.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

final class EnsureIdempotency
{
    private const int TTL = 86_400;

    public function handle(Request $request, Closure $next): Response
    {
        $key = $request->header('Idempotency-Key');

        if ($key === null || ! $request->isMethod('post')) {
            return $next($request);
        }

        $cacheKey = sprintf('idempotency:%s:%s', $request->user()?->id ?? 'guest', $key);

        // атомарная блокировка: два одновременных запроса не пройдут оба
        $lock = Cache::lock("{$cacheKey}:lock", 10);

        if (! $lock->get()) {
            return response()->json([
                'message' => 'Запрос с этим ключом уже обрабатывается.',
                'code'    => 'idempotency_in_progress',
            ], 409);
        }

        try {
            if ($cached = Cache::get($cacheKey)) {
                return response($cached['body'], $cached['status'])
                    ->header('Content-Type', 'application/json')
                    ->header('Idempotent-Replay', 'true');
            }

            $response = $next($request);

            if ($response->isSuccessful()) {
                Cache::put($cacheKey, [
                    'status' => $response->getStatusCode(),
                    'body'   => $response->getContent(),
                ], self::TTL);
            }

            return $response;
        } finally {
            $lock->release();
        }
    }
}

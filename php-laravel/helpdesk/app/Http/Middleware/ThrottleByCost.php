<?php
// app/Http/Middleware/ThrottleByCost.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\RateLimiter;
use Symfony\Component\HttpFoundation\Response;

final class ThrottleByCost
{
    public function handle(Request $request, Closure $next, int $maxCost = 100): Response
    {
        $key = 'cost:' . ($request->user()?->id ?? $request->ip());
        $cost = $this->costOf($request);

        if (RateLimiter::tooManyAttempts($key, $maxCost)) {
            return response()->json([
                'message'     => 'Превышен лимит нагрузки.',
                'code'        => 'too_many_requests',
                'retry_after' => RateLimiter::availableIn($key),
            ], 429, ['Retry-After' => RateLimiter::availableIn($key)]);
        }

        RateLimiter::increment($key, amount: $cost, decaySeconds: 60);

        return $next($request);
    }

    private function costOf(Request $request): int
    {
        $perPage = $request->integer('per_page', 20);

        return match (true) {
            $request->routeIs('stats.export') => 50,
            $request->routeIs('tickets.index') => max(1, (int) ceil($perPage / 20)),
            $request->isMethod('GET')          => 1,
            default                            => 5,
        };
    }
}

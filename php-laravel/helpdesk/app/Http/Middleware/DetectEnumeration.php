<?php
// app/Http/Middleware/DetectEnumeration.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Symfony\Component\HttpFoundation\Response;

final class DetectEnumeration
{
    private const int THRESHOLD = 20;

    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        if (in_array($response->getStatusCode(), [403, 404], strict: true)) {
            $key = 'denied:' . ($request->user()?->id ?? $request->ip());
            $count = Cache::increment($key);
            Cache::put($key, $count, now()->addMinutes(10));

            if ($count === self::THRESHOLD) {
                logger()->warning('security.enumeration_suspected', [
                    'user'  => $request->user()?->id,
                    'ip'    => $request->ip(),
                    'path'  => $request->path(),
                    'count' => $count,
                ]);
            }
        }

        return $response;
    }
}

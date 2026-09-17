<?php
// app/Http/Middleware/DeprecateApiVersion.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Symfony\Component\HttpFoundation\Response;

final class DeprecateApiVersion
{
    public function handle(Request $request, Closure $next, string $sunset): Response
    {
        $response = $next($request);

        logger()->info('api.deprecated_version_used', [
            'path'   => $request->path(),
            'client' => $request->userAgent(),
            'user'   => $request->user()?->id,
        ]);

        return $response->withHeaders([
            'Deprecation' => 'true',
            'Sunset'      => Carbon::parse($sunset)->toRfc7231String(),
            'Link'        => '<https://docs.helpdesk.local/api/v2>; rel="successor-version"',
        ]);
    }
}

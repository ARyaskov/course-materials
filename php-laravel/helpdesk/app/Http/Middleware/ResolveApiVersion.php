<?php
// app/Http/Middleware/ResolveApiVersion.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class ResolveApiVersion
{
    private const string DEFAULT = 'v1';

    private const array SUPPORTED = ['v1', 'v2'];

    public function handle(Request $request, Closure $next): Response
    {
        $accept = $request->header('Accept', '');

        preg_match('/application\/vnd\.helpdesk\.(v\d+)\+json/', $accept, $matches);

        $version = $matches[1] ?? self::DEFAULT;

        if (! in_array($version, self::SUPPORTED, strict: true)) {
            return response()->json([
                'message' => "Версия API {$version} не поддерживается.",
                'code'    => 'unsupported_api_version',
                'supported' => self::SUPPORTED,
            ], 406);
        }

        $request->attributes->set('api_version', $version);

        return $next($request)->header('X-Api-Version', $version);
    }
}

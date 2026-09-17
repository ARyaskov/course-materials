<?php
// app/Http/Middleware/ApiHeaders.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Context;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

final class ApiHeaders
{
    public function handle(Request $request, Closure $next): Response
    {
        $requestId = $request->header('X-Request-Id') ?? (string) Str::uuid7();

        Context::add([
            'request_id' => $requestId,
            'route'      => $request->route()?->getName(),
            'method'     => $request->method(),
            'ip'         => $request->ip(),
        ]);

        return $next($request)->header('X-Request-Id', $requestId);
    }
}

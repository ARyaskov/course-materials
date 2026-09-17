<?php
// app/Http/Middleware/SecurityHeaders.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class SecurityHeaders
{
    public function handle(Request $request, Closure $next): Response
    {
        return $next($request)->withHeaders([
            'X-Content-Type-Options'    => 'nosniff',
            'X-Frame-Options'           => 'DENY',
            'Referrer-Policy'           => 'no-referrer',
            'Cache-Control'             => 'no-store',
            'Strict-Transport-Security' => 'max-age=31536000; includeSubDomains',
        ]);
    }
}

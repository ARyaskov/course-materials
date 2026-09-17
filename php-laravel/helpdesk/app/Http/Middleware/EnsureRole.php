<?php
// app/Http/Middleware/EnsureRole.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class EnsureRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $userRole = $request->user()?->role->value;

        if (! in_array($userRole, $roles, strict: true)) {
            return response()->json([
                'message'  => 'Недостаточно прав.',
                'code'     => 'role_required',
                'required' => $roles,
            ], 403);
        }

        return $next($request);
    }
}

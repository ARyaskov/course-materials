<?php
// app/Http/Middleware/EnsureUserIsAgent.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class EnsureUserIsAgent
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()?->isAgent() !== true) {
            return response()->json([
                'message' => 'Операция доступна только сотрудникам поддержки.',
                'code'    => 'agent_required',
            ], 403);
        }

        return $next($request);
    }
}

<?php
// app/Http/Middleware/RecordAudit.php
declare(strict_types=1);

namespace App\Http\Middleware;

use App\Attributes\AuditAction;
use App\Models\AuditLog;
use Closure;
use Illuminate\Http\Request;
use ReflectionMethod;
use Symfony\Component\HttpFoundation\Response;

final class RecordAudit
{
    private const array HIDDEN = ['password', 'password_confirmation', 'token'];

    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);

        $action = $this->actionFor($request);

        if ($action !== null && $response->isSuccessful()) {
            AuditLog::query()->create([
                'action'     => $action->action,
                'user_id'    => $request->user()?->id,
                'ip'         => $request->ip(),
                'payload'    => $action->storePayload ? $request->except(self::HIDDEN) : null,
                'request_id' => $response->headers->get('X-Request-Id'),
            ]);
        }

        return $response;
    }

    private function actionFor(Request $request): ?AuditAction
    {
        $actionName = $request->route()?->getActionName();

        if ($actionName === null || ! str_contains($actionName, '@')) {
            return null;
        }

        [$class, $method] = explode('@', $actionName);

        $attributes = new ReflectionMethod($class, $method)->getAttributes(AuditAction::class);

        return $attributes === [] ? null : $attributes[0]->newInstance();
    }
}

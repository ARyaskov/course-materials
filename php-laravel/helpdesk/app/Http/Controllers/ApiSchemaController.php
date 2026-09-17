<?php
// app/Http/Controllers/ApiSchemaController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use App\Enums\ErrorCode;
use Illuminate\Http\JsonResponse;

final class ApiSchemaController extends Controller
{
    public function __invoke(): JsonResponse
    {
        return $this->ok([
            'version'  => 'v1',
            'envelope' => [
                'success' => ['data' => 'object|array', 'links?' => 'object', 'meta?' => 'object'],
                'error'   => ['message' => 'string', 'code' => 'string', 'meta' => 'object'],
            ],
            'error_codes' => collect(ErrorCode::cases())
                ->map(fn (ErrorCode $c): array => [
                    'code'             => $c->value,
                    'status'           => $c->httpStatus(),
                    'retryable'        => $c->isRetryable(),
                    'requires_refresh' => $c->requiresRefresh(),
                ])
                ->values(),
        ]);
    }
}

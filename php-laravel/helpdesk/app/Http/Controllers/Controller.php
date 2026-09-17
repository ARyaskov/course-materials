<?php
// app/Http/Controllers/Controller.php
declare(strict_types=1);

namespace App\Http\Controllers;

use Illuminate\Foundation\Auth\Access\AuthorizesRequests;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Response;

abstract class Controller
{
    use AuthorizesRequests;

    protected function ok(mixed $data): JsonResponse
    {
        return response()->json(['data' => $data]);
    }

    protected function created(mixed $data, string $location): JsonResponse
    {
        return response()->json(['data' => $data], 201, ['Location' => $location]);
    }

    protected function accepted(string $taskId, string $location): JsonResponse
    {
        return response()->json(
            ['data' => ['task_id' => $taskId, 'status' => 'queued']],
            202,
            ['Location' => $location],
        );
    }

    protected function noContent(): Response
    {
        return response()->noContent();
    }
}

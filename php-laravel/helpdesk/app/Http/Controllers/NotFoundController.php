<?php
// app/Http/Controllers/NotFoundController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use Illuminate\Http\JsonResponse;

final class NotFoundController extends Controller
{
    public function __invoke(): JsonResponse
    {
        return response()->json([
            'message' => 'Эндпоинт не найден.',
            'code'    => 'endpoint_not_found',
        ], 404);
    }
}

<?php

declare(strict_types=1);

use Illuminate\Support\Facades\Route;

// HelpDesk — чистый JSON API; веб-маршрутов у проекта нет.
// Файл оставлен, чтобы `withRouting(web: ...)` в bootstrap/app.php имел цель.
Route::get('/', fn () => response()->json([
    'name' => config('app.name'),
    'api' => url('/api/v1'),
    'health' => url('/up'),
]));

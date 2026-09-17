<?php

declare(strict_types=1);

use App\Http\Controllers\ApiSchemaController;
use App\Http\Controllers\AttachmentController;
use App\Http\Controllers\AuthController;
use App\Http\Controllers\CommentController;
use App\Http\Controllers\PasswordResetController;
use App\Http\Controllers\Ticket\CloseTicketController;
use App\Http\Controllers\TicketController;
use App\Http\Controllers\TicketExportController;
use App\Http\Controllers\TicketStatsController;
use Illuminate\Support\Facades\Route;

// ---------- публичные ----------

Route::get('schema/errors', ApiSchemaController::class)->name('schema.errors');

Route::post('auth/register', [AuthController::class, 'register'])
    ->middleware('throttle:register')
    ->name('auth.register');

Route::post('auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:login')
    ->name('auth.login');

Route::post('auth/password/request', [PasswordResetController::class, 'request'])
    ->middleware('throttle:password-reset')
    ->name('auth.password.request');

// ---------- защищённые ----------

Route::middleware('auth:sanctum')->group(function (): void {
    Route::get('auth/me', [AuthController::class, 'me'])->name('auth.me');
    Route::post('auth/logout', [AuthController::class, 'logout'])->name('auth.logout');
    Route::post('auth/logout-all', [AuthController::class, 'logoutAll'])->name('auth.logout.all');
    Route::post('auth/refresh', [AuthController::class, 'refresh'])->name('auth.refresh');
    Route::get('auth/sessions', [AuthController::class, 'sessions'])->name('auth.sessions');
    Route::delete('auth/sessions/{tokenId}', [AuthController::class, 'revoke'])->name('auth.sessions.revoke');

    Route::apiResource('tickets', TicketController::class)
        ->middlewareFor(['store', 'update', 'destroy'], 'throttle:writes');

    Route::prefix('tickets/{ticket}')->name('tickets.')->group(function (): void {
        Route::post('close', CloseTicketController::class)
            ->middleware(['agent', 'idempotent'])
            ->name('close');

        Route::post('reopen', [TicketController::class, 'reopen'])->name('reopen');

        Route::post('assign', [TicketController::class, 'assign'])
            ->middleware(['agent', 'idempotent'])
            ->name('assign');

        Route::post('attachments', [AttachmentController::class, 'store'])
            ->middleware('throttle:uploads')
            ->name('attachments.store');
    });

    Route::post('tickets/{ticket}/restore', [TicketController::class, 'restore'])
        ->withTrashed()   // иначе привязка не найдёт удалённую запись
        ->name('tickets.restore');

    Route::get('attachments/{attachment}/download', [AttachmentController::class, 'download'])
        ->name('attachments.download');

    Route::apiResource('tickets.comments', CommentController::class)
        ->shallow()
        ->only(['index', 'store', 'destroy']);

    Route::get('stats', TicketStatsController::class)->name('stats');

    Route::get('stats/export', TicketExportController::class)
        ->middleware('throttle:reports')
        ->name('stats.export');

    // только для сотрудников поддержки
    Route::middleware('agent')->prefix('agent')->name('agent.')->group(function (): void {
        Route::get('queue', [TicketController::class, 'queue'])->name('queue');
        Route::get('tickets/unassigned', [TicketController::class, 'unassigned'])->name('unassigned');
    });
});

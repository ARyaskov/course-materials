<?php

declare(strict_types=1);

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\BookingController;
use App\Http\Controllers\Api\V1\EventBookingController;
use App\Http\Controllers\Api\V1\EventController;
use Illuminate\Support\Facades\Route;

// ---------- публичные ----------

Route::post('register', [AuthController::class, 'register'])->name('register');
Route::post('login', [AuthController::class, 'login'])->middleware('throttle:10,1')->name('login');

Route::get('events', [EventController::class, 'index'])->name('events.index');
Route::get('events/{event}', [EventController::class, 'show'])->name('events.show');

// ---------- защищённые ----------

Route::middleware('auth:sanctum')->group(function (): void {
    Route::post('logout', [AuthController::class, 'logout'])->name('logout');
    Route::post('logout-all', [AuthController::class, 'logoutAll'])->name('logout.all');

    Route::middleware('abilities:events:manage')->group(function (): void {
        Route::post('events', [EventController::class, 'store'])->name('events.store');
        Route::patch('events/{event}', [EventController::class, 'update'])->name('events.update');
        Route::delete('events/{event}', [EventController::class, 'destroy'])->name('events.destroy');
        Route::post('events/{event}/publish', [EventController::class, 'publish'])->name('events.publish');
        Route::get('events/{event}/bookings', [EventBookingController::class, 'index'])->name('events.bookings.index');
    });

    Route::middleware('abilities:bookings:manage')->group(function (): void {
        Route::post('events/{event}/bookings', [EventBookingController::class, 'store'])
            ->name('events.bookings.store');
        Route::get('bookings', [BookingController::class, 'index'])->name('bookings.index');
        Route::get('bookings/{booking}', [BookingController::class, 'show'])->name('bookings.show');
        Route::post('bookings/{booking}/confirm', [BookingController::class, 'confirm'])->name('bookings.confirm');
        Route::delete('bookings/{booking}', [BookingController::class, 'destroy'])->name('bookings.destroy');
    });
});

Route::scopeBindings();

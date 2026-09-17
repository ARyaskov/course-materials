<?php

declare(strict_types=1);

use App\Exceptions\Booking\DuplicateBookingException;
use App\Exceptions\Booking\EventNotBookableException;
use App\Exceptions\Booking\InvalidTransitionException;
use App\Exceptions\Booking\NotEnoughSeatsException;
use App\Exceptions\Event\EventHasBookingsException;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__ . '/../routes/web.php',
        api: __DIR__ . '/../routes/api/v1.php',
        apiPrefix: 'api/v1',
        commands: __DIR__ . '/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->throttleApi('120,1');
        $middleware->preventRequestsDuringMaintenance(except: ['up', 'api/v1/health']);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->render(fn (NotEnoughSeatsException $e, Request $r) => response()->json([
            'message' => 'Недостаточно свободных мест.',
            'code' => 'not_enough_seats',
            'requested' => $e->requested,
            'available' => $e->available,
            'meta' => ['retryable' => true, 'requires_refresh' => true],
        ], 409));

        $exceptions->render(fn (DuplicateBookingException $e, Request $r) => response()->json([
            'message' => 'У вас уже есть активная бронь на это мероприятие.',
            'code' => 'duplicate_booking',
            'meta' => ['retryable' => false, 'requires_refresh' => true],
        ], 409));

        $exceptions->render(fn (EventNotBookableException $e, Request $r) => response()->json([
            'message' => 'Бронирование этого мероприятия недоступно.',
            'code' => 'event_not_bookable',
            'meta' => ['retryable' => false, 'requires_refresh' => true],
        ], 409));

        $exceptions->render(fn (InvalidTransitionException $e, Request $r) => response()->json([
            'message' => "Переход из «{$e->from->value}» в «{$e->to->value}» недопустим.",
            'code' => 'invalid_transition',
            'meta' => ['retryable' => false, 'requires_refresh' => true],
        ], 409));

        $exceptions->render(fn (EventHasBookingsException $e, Request $r) => response()->json([
            'message' => 'Мероприятие с активными бронями нельзя удалить.',
            'code' => 'event_has_bookings',
            'active_bookings' => $e->activeBookings,
            'meta' => [
                'retryable' => false,
                'requires_refresh' => false,
                'request_id' => $r->header('X-Request-Id'),
            ],
        ], 409));

        $exceptions->render(fn (AuthenticationException $e, Request $r) => response()->json([
            'message' => 'Требуется авторизация.',
            'code' => 'unauthenticated',
            'meta' => ['retryable' => false, 'requires_refresh' => true],
        ], 401));

        $exceptions->render(fn (AuthorizationException $e, Request $r) => response()->json([
            'message' => $e->getMessage() ?: 'Недостаточно прав.',
            'code' => $e->response()?->code() ?? 'forbidden',
            'meta' => ['retryable' => false, 'requires_refresh' => false],
        ], $e->response()?->status() ?? 403));
    })
    ->create();

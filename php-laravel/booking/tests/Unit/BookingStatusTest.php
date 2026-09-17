<?php
// tests/Unit/BookingStatusTest.php
declare(strict_types=1);

use App\Enums\BookingStatus;

test('места занимают только активные статусы', function (): void {
    expect(BookingStatus::Held->occupiesSeats())->toBeTrue()
        ->and(BookingStatus::Confirmed->occupiesSeats())->toBeTrue()
        ->and(BookingStatus::Cancelled->occupiesSeats())->toBeFalse()
        ->and(BookingStatus::Expired->occupiesSeats())->toBeFalse();
});

test('из конечного состояния переходов нет', function (BookingStatus $status): void {
    expect($status->allowedTransitions())->toBeEmpty();
})->with([BookingStatus::Cancelled, BookingStatus::Expired]);

test('подтверждённую бронь нельзя подтвердить повторно', function (): void {
    expect(BookingStatus::Confirmed->canTransitionTo(BookingStatus::Confirmed))->toBeFalse();
});

<?php
// tests/Unit/Enums/TicketStatusTest.php
declare(strict_types=1);

use App\Enums\TicketStatus;

it('разрешает переход из открытой в закрытую', function (): void {
    expect(TicketStatus::Open->canTransitionTo(TicketStatus::Closed))->toBeTrue();
});

it('запрещает переход из закрытой куда-либо', function (): void {
    expect(TicketStatus::Closed->allowedTransitions())->toBeEmpty();

    foreach (TicketStatus::cases() as $status) {
        expect(TicketStatus::Closed->canTransitionTo($status))->toBeFalse();
    }
});

it('определяет финальный статус', function (TicketStatus $status, bool $isFinal): void {
    expect($status->isFinal())->toBe($isFinal);
})->with([
    'открыта'    => [TicketStatus::Open, false],
    'ждёт'       => [TicketStatus::Pending, false],
    'решена'     => [TicketStatus::Resolved, false],
    'закрыта'    => [TicketStatus::Closed, true],
]);

it('у каждого статуса есть подпись', function (TicketStatus $status): void {
    expect($status->label())->toBeString()->not->toBeEmpty();
})->with(TicketStatus::cases());

it('переходы согласованы: если A → B разрешён, B есть в списке', function (): void {
    foreach (TicketStatus::cases() as $from) {
        foreach ($from->allowedTransitions() as $to) {
            expect($from->canTransitionTo($to))->toBeTrue();
        }
    }
});

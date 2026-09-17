<?php
// tests/Unit/DTO/TicketFiltersTest.php
declare(strict_types=1);

use App\DTO\TicketFilters;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;

it('пустые фильтры распознаются', function (): void {
    expect(new TicketFilters()->isEmpty())->toBeTrue()
        ->and(new TicketFilters(unansweredOnly: true)->isEmpty())->toBeFalse();
});

it('ключ кэша устойчив к порядку', function (): void {
    $a = new TicketFilters(status: TicketStatus::Open, priorities: [TicketPriority::High], search: 'vpn');
    $b = new TicketFilters(search: 'vpn', priorities: [TicketPriority::High], status: TicketStatus::Open);

    expect($a->cacheKey(7))->toBe($b->cacheKey(7));
});

it('разные фильтры дают разные ключи', function (): void {
    $open = new TicketFilters(status: TicketStatus::Open);
    $closed = new TicketFilters(status: TicketStatus::Closed);

    expect($open->cacheKey(7))->not->toBe($closed->cacheKey(7));
});

it('ключ зависит от пользователя', function (): void {
    $filters = new TicketFilters(status: TicketStatus::Open);

    expect($filters->cacheKey(7))->not->toBe($filters->cacheKey(8));
});

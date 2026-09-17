<?php
// tests/Unit/TicketDataTest.php
declare(strict_types=1);

use App\DTO\TicketData;
use App\DTO\TicketFilters;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;

it('отклоняет критичную заявку без исполнителя', function (): void {
    expect(fn () => new TicketData(
        subject: 'Не работает VPN',
        body: 'Текст заявки',
        priority: TicketPriority::Critical,
    ))->toThrow(InvalidArgumentException::class, 'требует исполнителя');
});

it('не принимает больше пяти меток', function (): void {
    expect(fn () => new TicketData(
        subject: 'Не работает VPN',
        body: 'Текст заявки',
        tags: ['a', 'b', 'c', 'd', 'e', 'f'],
    ))->toThrow(InvalidArgumentException::class);
});

it('withPriority возвращает копию', function (): void {
    $data = new TicketData('Тема заявки', 'Текст заявки');
    $changed = $data->withPriority(TicketPriority::High);

    expect($data->priority)->toBe(TicketPriority::Normal)
        ->and($changed->priority)->toBe(TicketPriority::High);
});

it('toAttributes убирает null-поля', function (): void {
    $data = new TicketData('Тема заявки', 'Текст заявки');

    expect($data->toAttributes())
        ->toHaveKeys(['subject', 'body', 'priority'])
        ->not->toHaveKey('assignee_id');
});

it('отклоняет лишний ключ при распаковке', function (): void {
    expect(fn () => new TicketData(...[
        'subject' => 'Тема', 'body' => 'Текст', 'unknown' => 1,
    ]))->toThrow(Error::class, 'Unknown named parameter');
});

it('фильтры дают стабильный ключ кэша', function (): void {
    $a = new TicketFilters(status: TicketStatus::Open, search: 'vpn');
    $b = new TicketFilters(status: TicketStatus::Open, search: 'vpn');
    $c = new TicketFilters(status: TicketStatus::Closed, search: 'vpn');

    expect($a->cacheKey())->toBe($b->cacheKey())
        ->and($a->cacheKey())->not->toBe($c->cacheKey());
});

it('isEmpty распознаёт отсутствие фильтров', function (): void {
    expect(new TicketFilters()->isEmpty())->toBeTrue()
        ->and(new TicketFilters(unansweredOnly: true)->isEmpty())->toBeFalse();
});

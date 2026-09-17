<?php
// tests/Integration/TicketServiceTest.php
declare(strict_types=1);

use App\DTO\TicketData;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Events\TicketClosed;
use App\Events\TicketCreated;
use App\Exceptions\InvalidStatusTransitionException;
use App\Exceptions\TicketLimitExceededException;
use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketService;
use Illuminate\Support\Facades\Event;

beforeEach(function (): void {
    Event::fake();

    $this->service = app(TicketService::class);
    $this->author = User::factory()->create();
    $this->agent = User::factory()->agent()->create();
});

it('создаёт заявку с метками и системным комментарием', function (): void {
    Tag::factory()->create(['slug' => 'vpn']);

    $ticket = $this->service->create(
        $this->author,
        new TicketData('Не работает VPN', 'Достаточно длинный текст', TicketPriority::High, tags: ['vpn']),
    );

    expect($ticket->author_id)->toBe($this->author->id)
        ->and($ticket->status)->toBe(TicketStatus::Open)
        ->and($ticket->priority)->toBe(TicketPriority::High)
        ->and($ticket->tags)->toHaveCount(1)
        ->and($ticket->comments()->where('is_system', true)->count())->toBe(1);

    Event::assertDispatched(TicketCreated::class);
});

it('проверяет лимит до создания', function (): void {
    config(['helpdesk.limits.open_tickets_per_user' => 3]);

    Ticket::factory()->count(3)->for($this->author, 'author')->create(['status' => TicketStatus::Open]);

    expect(fn () => $this->service->create($this->author, new TicketData('Тема заявки', 'Текст заявки')))
        ->toThrow(TicketLimitExceededException::class);

    expect(Ticket::query()->count())->toBe(3);
    Event::assertNotDispatched(TicketCreated::class);
});

it('закрытые заявки не считаются в лимите', function (): void {
    config(['helpdesk.limits.open_tickets_per_user' => 3]);

    Ticket::factory()->count(5)->for($this->author, 'author')->closed()->create();

    $ticket = $this->service->create($this->author, new TicketData('Тема заявки', 'Текст заявки'));

    expect($ticket->exists)->toBeTrue();
});

it('закрывает заявку', function (): void {
    $ticket = Ticket::factory()->create(['status' => TicketStatus::Open]);

    $closed = $this->service->close($ticket, $this->agent, 'Настройки исправлены.');

    expect($closed->status)->toBe(TicketStatus::Closed)
        ->and($closed->resolved_at)->not->toBeNull()
        ->and($closed->resolution)->toBe('Настройки исправлены.');

    Event::assertDispatched(TicketClosed::class, fn (TicketClosed $e): bool
        => $e->ticket->id === $ticket->id && $e->actor->id === $this->agent->id);
});

it('не закрывает закрытую', function (): void {
    $ticket = Ticket::factory()->closed()->create();

    expect(fn () => $this->service->close($ticket, $this->agent))
        ->toThrow(InvalidStatusTransitionException::class);

    Event::assertNotDispatched(TicketClosed::class);
});

it('откатывает всё при сбое внутри транзакции', function (): void {
    Comment::creating(fn () => throw new RuntimeException('сбой при создании комментария'));

    $before = Ticket::query()->count();

    try {
        $this->service->create($this->author, new TicketData('Тема заявки', 'Текст заявки'));
    } catch (RuntimeException) {
        //
    }

    expect(Ticket::query()->count())->toBe($before);
    Event::assertNotDispatched(TicketCreated::class);
});

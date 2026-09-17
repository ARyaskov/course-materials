<?php
// tests/Unit/TicketServiceTest.php
declare(strict_types=1);

use App\DTO\TicketData;
use App\Enums\TicketPriority;
use App\Enums\TicketStatus;
use App\Events\TicketCreated;
use App\Exceptions\TicketLimitExceededException;
use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use App\Services\TicketService;
use Illuminate\Support\Facades\Event;

it('создаёт заявку с метками и системным комментарием', function (): void {
    Event::fake();

    $author = User::factory()->create();
    Tag::factory()->create(['slug' => 'vpn']);

    $ticket = app(TicketService::class)->create(
        $author,
        new TicketData('Не работает VPN', 'Достаточно длинный текст', TicketPriority::High, tags: ['vpn']),
    );

    expect($ticket->author_id)->toBe($author->id)
        ->and($ticket->tags)->toHaveCount(1)
        ->and($ticket->comments()->where('is_system', true)->count())->toBe(1);

    Event::assertDispatched(TicketCreated::class);
});

it('проверяет лимит до транзакции', function (): void {
    $author = User::factory()->create();
    Ticket::factory()->count(20)->for($author, 'author')->create(['status' => TicketStatus::Open]);

    expect(fn () => app(TicketService::class)->create($author, new TicketData('Тема заявки', 'Текст заявки')))
        ->toThrow(TicketLimitExceededException::class);

    expect(Ticket::query()->count())->toBe(20);   // ничего не создано
});

it('сервис не зависит от HTTP', function (): void {
    $reflection = new ReflectionClass(TicketService::class);

    foreach ($reflection->getMethods(ReflectionMethod::IS_PUBLIC) as $method) {
        foreach ($method->getParameters() as $parameter) {
            $type = (string) $parameter->getType();

            expect($type)->not->toContain('Illuminate\Http\Request');
        }

        expect((string) $method->getReturnType())->not->toContain('Illuminate\Http\JsonResponse');
    }
});

it('составной сценарий эскалации повышает приоритет', function (): void {
    Event::fake();

    $system = User::factory()->admin()->create();

    Ticket::factory()->count(3)->create([
        'priority'   => TicketPriority::Normal,
        'created_at' => now()->subDays(5),
        'sla_hours'  => 24,
    ]);

    $escalated = app(\App\Services\TicketEscalationService::class)->escalateOverdue($system);

    expect($escalated)->toHaveCount(3);

    foreach ($escalated as $ticket) {
        expect($ticket->fresh()->priority)->toBe(TicketPriority::High);
    }
});

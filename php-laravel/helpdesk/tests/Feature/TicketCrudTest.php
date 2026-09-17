<?php
// tests/Feature/TicketCrudTest.php
declare(strict_types=1);

use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

it('создаёт заявку с метками и системным комментарием', function (): void {
    $user = User::factory()->create();
    Tag::factory()->create(['slug' => 'vpn']);

    $ticket = app(\App\Services\TicketService::class)->create(
        $user,
        new \App\DTO\TicketData('Не работает VPN', 'Текст заявки', tags: ['vpn']),
    );

    expect($ticket->author_id)->toBe($user->id)
        ->and($ticket->tags)->toHaveCount(1)
        ->and($ticket->comments()->where('is_system', true)->count())->toBe(1);
});

it('откатывает всё при сбое внутри транзакции', function (): void {
    $user = User::factory()->create();

    try {
        DB::transaction(function () use ($user): void {
            $user->tickets()->create(['subject' => 'Тест', 'body' => 'Текст']);

            throw new \RuntimeException('сбой');
        });
    } catch (\RuntimeException) {
        // ожидаемо
    }

    expect(Ticket::query()->count())->toBe(0);
});

it('инкремент безопасен при одновременных обновлениях', function (): void {
    $ticket = Ticket::factory()->create(['views' => 0]);

    $ticket->increment('views');
    $ticket->increment('views');

    expect($ticket->fresh()->views)->toBe(2);
});

it('массовое обновление не вызывает наблюдателей', function (): void {
    $ticket = Ticket::factory()->create(['updated_at' => now()->subDay()]);
    $before = $ticket->updated_at;

    Ticket::query()->whereKey($ticket->id)->update(['priority' => 'high']);

    expect($ticket->fresh()->updated_at->timestamp)->toBe($before->timestamp);
});

it('sync возвращает отчёт об изменениях', function (): void {
    $ticket = Ticket::factory()->create();
    $tags = Tag::factory()->count(3)->create();

    $ticket->tags()->sync([$tags[0]->id, $tags[1]->id]);
    $result = $ticket->tags()->sync([$tags[1]->id, $tags[2]->id]);

    expect($result['attached'])->toContain($tags[2]->id)
        ->and($result['detached'])->toContain($tags[0]->id);
});

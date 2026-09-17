<?php
// tests/Feature/TransactionsTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;
use App\Jobs\NotifyTicketCreated;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Queue;

it('откатывает всё при сбое', function (): void {
    $user = User::factory()->create();

    try {
        DB::transaction(function () use ($user): void {
            $ticket = $user->tickets()->create(['subject' => 'Тест', 'body' => 'Текст заявки']);
            $ticket->comments()->create(['author_id' => $user->id, 'body' => 'Комментарий']);

            throw new \RuntimeException('сбой');
        });
    } catch (\RuntimeException) {
        //
    }

    expect(Ticket::query()->count())->toBe(0)
        ->and(Comment::query()->count())->toBe(0);
});

it('вложенная транзакция откатывается точкой сохранения', function (): void {
    $user = User::factory()->create();

    DB::transaction(function () use ($user): void {
        $ticket = $user->tickets()->create(['subject' => 'Внешняя', 'body' => 'Текст заявки']);

        try {
            DB::transaction(function () use ($ticket, $user): void {
                $ticket->comments()->create(['author_id' => $user->id, 'body' => 'Комментарий']);

                throw new \RuntimeException('сбой');
            });
        } catch (\RuntimeException) {
            //
        }
    });

    expect(Ticket::query()->count())->toBe(1)
        ->and(Comment::query()->count())->toBe(0);
});

it('задача ставится только после фиксации', function (): void {
    Queue::fake();
    $user = User::factory()->create();

    try {
        DB::transaction(function () use ($user): void {
            $ticket = $user->tickets()->create(['subject' => 'Тест', 'body' => 'Текст заявки']);

            NotifyTicketCreated::dispatch($ticket)->afterCommit();

            throw new \RuntimeException('сбой');
        });
    } catch (\RuntimeException) {
        //
    }

    Queue::assertNothingPushed();
});

it('атомарное назначение не допускает двойного', function (): void {
    $ticket = Ticket::factory()->create(['assignee_id' => null]);
    $a = User::factory()->agent()->create();
    $b = User::factory()->agent()->create();

    $first = Ticket::query()->whereKey($ticket->id)->whereNull('assignee_id')
        ->update(['assignee_id' => $a->id]);
    $second = Ticket::query()->whereKey($ticket->id)->whereNull('assignee_id')
        ->update(['assignee_id' => $b->id]);

    expect($first)->toBe(1)->and($second)->toBe(0)
        ->and($ticket->fresh()->assignee_id)->toBe($a->id);
});

it('оптимистическая блокировка отклоняет устаревшую версию', function (): void {
    $ticket = Ticket::factory()->create(['version' => 1]);

    $service = app(\App\Services\TicketService::class);
    $data = new \App\DTO\TicketData('Новая тема', 'Новый текст заявки');

    $service->update($ticket, $data, expectedVersion: 1);

    expect(fn () => $service->update($ticket, $data, expectedVersion: 1))
        ->toThrow(\App\Exceptions\StaleDataException::class);
});

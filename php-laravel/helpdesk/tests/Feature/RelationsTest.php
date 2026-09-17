<?php
// tests/Feature/RelationsTest.php
declare(strict_types=1);

use App\Models\Attachment;
use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

it('создаёт комментарий через связь с подстановкой ключа', function (): void {
    $ticket = Ticket::factory()->create();
    $user = User::factory()->create();

    $comment = $ticket->comments()->create(['author_id' => $user->id, 'body' => 'Ответ']);

    expect($comment->ticket_id)->toBe($ticket->id);
});

it('count через метод не грузит записи', function (): void {
    $ticket = Ticket::factory()->has(Comment::factory()->count(50))->create();

    DB::enableQueryLog();
    $count = $ticket->comments()->count();

    expect($count)->toBe(50)
        ->and(DB::getQueryLog()[0]['query'])->toContain('count(*)');
});

it('latestOfMany отдаёт последний комментарий', function (): void {
    $ticket = Ticket::factory()->create();
    Comment::factory()->for($ticket)->create(['created_at' => now()->subDay(), 'body' => 'Старый']);
    Comment::factory()->for($ticket)->create(['created_at' => now(), 'body' => 'Новый']);

    expect($ticket->latestComment->body)->toBe('Новый');
});

it('hasManyThrough собирает комментарии заявок пользователя', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(2)->for($user, 'author')
        ->has(Comment::factory()->count(3))->create();

    expect($user->ticketComments()->count())->toBe(6);
});

it('полиморфная связь работает для заявки и комментария', function (): void {
    $ticket = Ticket::factory()->create();
    $comment = Comment::factory()->for($ticket)->create();

    $ticket->attachments()->create(Attachment::factory()->raw());
    $comment->attachments()->create(Attachment::factory()->raw());

    expect($ticket->attachments)->toHaveCount(1)
        ->and($comment->attachments)->toHaveCount(1)
        ->and($ticket->attachments->first()->attachable)->toBeInstanceOf(Ticket::class);
});

it('withDefault избавляет от проверки на null', function (): void {
    $ticket = Ticket::factory()->create(['assignee_id' => null]);

    expect($ticket->assignee->name)->toBe('Не назначен');
});

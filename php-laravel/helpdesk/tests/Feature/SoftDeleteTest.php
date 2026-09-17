<?php
// tests/Feature/SoftDeleteTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Tag;
use App\Models\Ticket;

it('удаляет мягко и скрывает из выборок', function (): void {
    $ticket = Ticket::factory()->create();

    $ticket->delete();

    expect(Ticket::query()->count())->toBe(0)
        ->and(Ticket::withTrashed()->count())->toBe(1)
        ->and($ticket->fresh()->trashed())->toBeTrue();
});

it('восстанавливает заявку вместе с комментариями', function (): void {
    $ticket = Ticket::factory()->has(Comment::factory()->count(3))->create();

    $ticket->delete();
    expect(Comment::query()->count())->toBe(0);

    $ticket->restore();
    expect(Comment::query()->count())->toBe(3);
});

it('маршрут восстановления находит удалённую заявку', function (): void {
    $ticket = Ticket::factory()->create();
    $ticket->delete();

    $this->actingAsAgent()
        ->postJson("/api/v1/tickets/{$ticket->id}/restore")
        ->assertOk();

    expect($ticket->fresh()->trashed())->toBeFalse();
});

it('позволяет создать метку с освободившимся slug', function (): void {
    Tag::factory()->create(['slug' => 'vpn'])->delete();

    $tag = Tag::query()->create(['slug' => 'vpn', 'name' => 'VPN']);

    expect($tag->exists)->toBeTrue()
        ->and(Tag::withTrashed()->where('slug', 'vpn')->count())->toBe(2);
});

it('полное удаление уносит комментарии каскадом', function (): void {
    $ticket = Ticket::factory()->has(Comment::factory()->count(2))->create();

    $ticket->forceDelete();

    expect(Comment::withTrashed()->count())->toBe(0);
});

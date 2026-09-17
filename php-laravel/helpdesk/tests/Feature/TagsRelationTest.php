<?php
// tests/Feature/TagsRelationTest.php
declare(strict_types=1);

use App\Models\Tag;
use App\Models\Ticket;
use App\Models\User;
use Illuminate\Support\Facades\DB;

it('sync заменяет набор меток и возвращает отчёт', function (): void {
    $ticket = Ticket::factory()->create();
    $tags = Tag::factory()->count(3)->create();

    $ticket->tags()->sync([$tags[0]->id, $tags[1]->id]);
    $result = $ticket->tags()->sync([$tags[1]->id, $tags[2]->id]);

    expect($ticket->fresh()->tags->pluck('id')->all())
        ->toEqualCanonicalizing([$tags[1]->id, $tags[2]->id])
        ->and($result['attached'])->toBe([$tags[2]->id])
        ->and($result['detached'])->toBe([$tags[0]->id]);
});

it('повторный attach нарушает уникальность', function (): void {
    $ticket = Ticket::factory()->create();
    $tag = Tag::factory()->create();

    $ticket->tags()->attach($tag->id);

    expect(fn () => $ticket->tags()->attach($tag->id))
        ->toThrow(\Illuminate\Database\UniqueConstraintViolationException::class);
});

it('syncWithoutDetaching идемпотентен', function (): void {
    $ticket = Ticket::factory()->create();
    $tag = Tag::factory()->create();

    $ticket->tags()->syncWithoutDetaching([$tag->id]);
    $ticket->tags()->syncWithoutDetaching([$tag->id]);

    expect($ticket->fresh()->tags)->toHaveCount(1);
});

it('сохраняет поля связи', function (): void {
    $ticket = Ticket::factory()->create();
    $tag = Tag::factory()->create();
    $user = User::factory()->create();

    $ticket->tags()->attach($tag->id, ['attached_by' => $user->id]);

    expect($ticket->fresh()->tags->first()->pivot->attached_by)->toBe($user->id)
        ->and($ticket->fresh()->tags->first()->pivot->created_at)->not->toBeNull();
});

it('находит заявки со всеми перечисленными метками', function (): void {
    $vpn = Tag::factory()->create(['slug' => 'vpn']);
    $net = Tag::factory()->create(['slug' => 'network']);

    $both = Ticket::factory()->create();
    $both->tags()->attach([$vpn->id, $net->id]);

    $one = Ticket::factory()->create();
    $one->tags()->attach($vpn->id);

    $found = Ticket::query()
        ->whereHas('tags', fn ($q) => $q->whereIn('slug', ['vpn', 'network']), '=', 2)
        ->pluck('id');

    expect($found->all())->toBe([$both->id]);
});

it('каскад убирает строки связи при полном удалении', function (): void {
    $ticket = Ticket::factory()->create();
    $ticket->tags()->attach(Tag::factory()->create()->id);

    $ticket->forceDelete();

    expect(DB::table('ticket_tag')->count())->toBe(0);
});

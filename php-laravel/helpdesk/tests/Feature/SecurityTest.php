<?php
// tests/Feature/SecurityTest.php
declare(strict_types=1);

use App\Models\Comment;
use App\Models\Ticket;
use App\Models\User;

it('нельзя получить роль администратора при регистрации', function (): void {
    $this->postJson('/api/v1/auth/register', [
        'name' => 'Пётр', 'email' => 'p@example.com',
        'password' => 'Str0ng-Passphrase-2026', 'password_confirmation' => 'Str0ng-Passphrase-2026',
        'role' => 'admin',
    ])->assertStatus(422);

    expect(User::query()->where('email', 'p@example.com')->first()?->role->value)->not->toBe('admin');
});

it('список не показывает чужие заявки', function (): void {
    $user = User::factory()->create();
    Ticket::factory()->count(2)->for($user, 'author')->create();
    Ticket::factory()->count(5)->create();

    $this->actingAs($user, 'sanctum')->getJson('/api/v1/tickets')->assertJsonCount(2, 'data');
});

it('комментарий чужой заявки недоступен', function (): void {
    $mine = Ticket::factory()->create();
    $foreign = Ticket::factory()->create();
    $comment = Comment::factory()->for($foreign)->create();

    $this->actingAs($mine->author, 'sanctum')
        ->getJson("/api/v1/tickets/{$mine->id}/comments/{$comment->id}")
        ->assertNotFound();
});

it('сортировка по произвольной колонке отклоняется', function (): void {
    $this->actingAsAgent()->getJson('/api/v1/tickets?sort=password')->assertStatus(422);
});

it('не принимает исполняемый файл под видом изображения', function (): void {
    $ticket = Ticket::factory()->create();

    $file = \Illuminate\Http\Testing\File::create('photo.png', 10);
    file_put_contents($file->getPathname(), "<?php system(\$_GET['c']); ?>");

    $this->actingAs($ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$ticket->id}/attachments", ['attachment' => $file])
        ->assertStatus(422);
});

it('не раскрывает внутренности при 500', function (): void {
    config(['app.debug' => false]);

    $this->mock(\App\Services\TicketService::class)
        ->shouldReceive('create')
        ->andThrow(new \RuntimeException('SQLSTATE[42P01]: relation "tickets" does not exist'));

    $response = $this->actingAsAgent()->postJson('/api/v1/tickets', [
        'subject' => 'Не работает VPN', 'body' => 'Достаточно длинный текст заявки',
    ]);

    expect($response->getContent())->not->toContain('SQLSTATE')->not->toContain('relation');
});

it('отдаёт заголовки безопасности', function (): void {
    $this->actingAsAgent()
        ->getJson('/api/v1/tickets')
        ->assertHeader('X-Content-Type-Options', 'nosniff')
        ->assertHeader('Cache-Control', 'no-store');
});

it('вложение недоступно без прав', function (): void {
    $ticket = Ticket::factory()->create();
    $attachment = $ticket->attachments()->create([
        'uploaded_by' => $ticket->author_id, 'path' => 'tickets/1/x.png',
        'original_name' => 'x.png', 'size_bytes' => 10, 'mime_type' => 'image/png',
    ]);

    $this->actingAs(User::factory()->create(), 'sanctum')
        ->get("/api/v1/attachments/{$attachment->id}")
        ->assertNotFound();
});

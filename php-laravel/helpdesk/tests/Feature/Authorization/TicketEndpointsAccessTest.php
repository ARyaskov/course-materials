<?php
// tests/Feature/Authorization/TicketEndpointsAccessTest.php
declare(strict_types=1);

use App\Models\Ticket;
use App\Models\User;

beforeEach(function (): void {
    $this->ticket = Ticket::factory()->create(['status' => 'open']);
    $this->stranger = User::factory()->create();
});

it('посторонний не получает 2xx ни на одном маршруте заявки', function (): void {
    $routes = [
        ['get',    "/api/v1/tickets/{$this->ticket->id}"],
        ['patch',  "/api/v1/tickets/{$this->ticket->id}"],
        ['put',    "/api/v1/tickets/{$this->ticket->id}"],
        ['delete', "/api/v1/tickets/{$this->ticket->id}"],
        ['post',   "/api/v1/tickets/{$this->ticket->id}/close"],
        ['post',   "/api/v1/tickets/{$this->ticket->id}/reopen"],
        ['post',   "/api/v1/tickets/{$this->ticket->id}/assign"],
        ['post',   "/api/v1/tickets/{$this->ticket->id}/comments"],
        ['post',   "/api/v1/tickets/{$this->ticket->id}/attachments"],
    ];

    foreach ($routes as [$method, $uri]) {
        $status = $this->actingAs($this->stranger, 'sanctum')->json($method, $uri, [])->status();

        expect($status)->toBeIn([403, 404, 422], "{$method} {$uri} вернул {$status}");
    }
});

it('без токена все маршруты дают 401', function (): void {
    $routes = [
        ['get',  '/api/v1/tickets'],
        ['post', '/api/v1/tickets'],
        ['get',  "/api/v1/tickets/{$this->ticket->id}"],
        ['post', "/api/v1/tickets/{$this->ticket->id}/close"],
    ];

    foreach ($routes as [$method, $uri]) {
        $this->json($method, $uri, [])
            ->assertUnauthorized()
            ->assertJsonPath('code', 'unauthenticated');
    }
});

it('чужая заявка отдаётся как 404, а не 403', function (): void {
    $this->actingAs($this->stranger, 'sanctum')
        ->getJson("/api/v1/tickets/{$this->ticket->id}")
        ->assertNotFound();
});

it('автор не может назначить исполнителя', function (): void {
    $agent = User::factory()->agent()->create();

    $this->actingAs($this->ticket->author, 'sanctum')
        ->postJson("/api/v1/tickets/{$this->ticket->id}/assign", ['assignee_id' => $agent->id])
        ->assertForbidden()
        ->assertJsonPath('code', 'forbidden');
});

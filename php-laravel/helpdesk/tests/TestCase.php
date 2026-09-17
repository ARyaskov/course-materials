<?php
// tests/TestCase.php
declare(strict_types=1);

namespace Tests;

use App\Models\User;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;

abstract class TestCase extends BaseTestCase
{
    /** Пользователь, от имени которого выполняется текущий тест. */
    public ?User $currentUser = null;

    protected function setUp(): void
    {
        parent::setUp();

        // защита от прогона на боевой базе
        $database = DB::connection()->getDatabaseName();

        if (! str_contains($database, 'test') && $database !== ':memory:') {
            $this->fail("Тесты запущены на базе «{$database}» — это не тестовая база.");
        }

        // строгий режим: N+1 и обращение к незагруженному падают
        Model::shouldBeStrict();

        // ни один тест не должен ходить в интернет
        Http::preventStrayRequests();

        // подробности ошибок в тестовом выводе
        config()->set('app.debug', true);
    }

    /** Возвращает сам тест, чтобы вызов можно было продолжить: actingAsAgent()->getJson(...). */
    public function actingAsAgent(?User $agent = null): static
    {
        $this->currentUser = $agent ?? User::factory()->agent()->create();

        return $this->actingAs($this->currentUser, 'sanctum');
    }

    public function actingAsAdmin(?User $admin = null): static
    {
        $this->currentUser = $admin ?? User::factory()->admin()->create();

        return $this->actingAs($this->currentUser, 'sanctum');
    }

    public function actingAsUser(?User $user = null): static
    {
        $this->currentUser = $user ?? User::factory()->create();

        return $this->actingAs($this->currentUser, 'sanctum');
    }

    /** @return array<string, mixed> */
    protected function validTicketPayload(array $overrides = []): array
    {
        return [
            'subject' => 'Не работает VPN',
            'body'    => 'С утра не подключается из дома, переустановка не помогла.',
            'priority'=> 'normal',
            ...$overrides,
        ];
    }
}

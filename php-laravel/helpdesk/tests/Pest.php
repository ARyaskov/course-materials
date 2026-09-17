<?php

declare(strict_types=1);

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

pest()->extend(TestCase::class)
    ->use(RefreshDatabase::class)
    ->in('Feature', 'Integration', 'Smoke');

pest()->extend(TestCase::class)->in('Architecture');

/**
 * Помощники возвращают сам тест, поэтому вызов продолжается цепочкой:
 * actingAsAgent()->getJson('/api/v1/tickets'). Созданный пользователь —
 * в $this->currentUser или через currentUser().
 */
function actingAsUser(?User $user = null): TestCase
{
    return test()->actingAsUser($user);
}

function actingAsAgent(?User $agent = null): TestCase
{
    return test()->actingAsAgent($agent);
}

function actingAsAdmin(?User $admin = null): TestCase
{
    return test()->actingAsAdmin($admin);
}

function currentUser(): User
{
    return test()->currentUser ?? throw new RuntimeException('Пользователь не задан: вызовите actingAs*() раньше.');
}

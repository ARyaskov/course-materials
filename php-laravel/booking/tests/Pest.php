<?php
// tests/Pest.php
declare(strict_types=1);

use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

pest()->extend(TestCase::class)
    ->use(RefreshDatabase::class)
    ->in('Feature');

function actingAsParticipant(?User $user = null): User
{
    $user ??= User::factory()->create();
    Sanctum::actingAs($user, ['bookings:manage']);

    return $user;
}

function actingAsOrganizer(?User $user = null): User
{
    $user ??= User::factory()->organizer()->create();
    Sanctum::actingAs($user, ['events:manage', 'bookings:manage']);

    return $user;
}

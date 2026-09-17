<?php
// database/seeders/UserSeeder.php
declare(strict_types=1);

namespace Database\Seeders;

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Database\Seeder;

final class UserSeeder extends Seeder
{
    public function run(): void
    {
        // предсказуемые учётки для входа на стенд; сидер идемпотентен —
        // повторный запуск не создаёт дублей и не падает на уникальном индексе
        $accounts = [
            ['admin@helpdesk.local', 'Администратор', UserRole::Admin],
            ['agent@helpdesk.local', 'Ирина Ковалёва', UserRole::Agent],
            ['user@helpdesk.local', 'Пётр Смирнов', UserRole::User],
        ];

        foreach ($accounts as [$email, $name, $role]) {
            User::query()->firstOrCreate(
                ['email' => $email],
                [
                    'name' => $name,
                    'password' => 'password',
                    'role' => $role,
                    'email_verified_at' => now(),
                ],
            );
        }

        // массовка
        User::factory()->count(5)->agent()->create();
        User::factory()->count(40)->create();
    }
}

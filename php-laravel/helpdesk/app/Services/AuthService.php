<?php
// app/Services/AuthService.php
declare(strict_types=1);

namespace App\Services;

use App\DTO\AuthResult;
use App\Enums\UserRole;
use App\Exceptions\InvalidCredentialsException;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

final readonly class AuthService
{
    /** @param  array{name: string, email: string, password: string}  $data */
    public function register(array $data): AuthResult
    {
        $user = DB::transaction(fn (): User => User::query()->create([
            'name'     => $data['name'],
            'email'    => $data['email'],
            'password' => $data['password'],   // хешируется приведением
            'role'     => UserRole::User,       // роль задаём здесь, не из запроса
        ]));

        return new AuthResult($user, $user->createToken('api')->plainTextToken);
    }

    public function login(string $email, string $password, string $device): AuthResult
    {
        $user = User::query()->where('email', mb_strtolower($email))->first();

        // проверяем хеш всегда — иначе по времени ответа видно, есть ли такой адрес
        $valid = $user !== null && Hash::check($password, $user->password);

        if (! $valid) {
            Hash::check($password, '$2y$12$' . str_repeat('x', 53));   // выравниваем время

            throw new InvalidCredentialsException();
        }

        if ($user->password_needs_rehash ?? Hash::needsRehash($user->password)) {
            $user->forceFill(['password' => $password])->save();
        }

        return new AuthResult($user, $user->createToken($device)->plainTextToken);
    }
}

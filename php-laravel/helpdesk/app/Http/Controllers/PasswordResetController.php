<?php
// app/Http/Controllers/PasswordResetController.php
declare(strict_types=1);

namespace App\Http\Controllers;

use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Password;
use Illuminate\Support\Str;

final class PasswordResetController extends Controller
{
    public function request(Request $request): JsonResponse
    {
        $request->validate(['email' => ['required', 'email']]);

        Password::sendResetLink(['email' => mb_strtolower($request->string('email')->toString())]);

        // ответ одинаков независимо от существования адреса
        return response()->json([
            'data' => ['message' => 'Если адрес зарегистрирован, письмо отправлено.'],
        ]);
    }

    public function reset(Request $request): JsonResponse
    {
        $request->validate([
            'token'    => ['required', 'string'],
            'email'    => ['required', 'email'],
            'password' => ['required', 'confirmed', \Illuminate\Validation\Rules\Password::defaults()],
        ]);

        $status = Password::reset(
            $request->only('email', 'password', 'password_confirmation', 'token'),
            function (User $user, string $password): void {
                $user->forceFill([
                    'password'       => $password,
                    'remember_token' => Str::random(60),
                ])->save();

                $user->tokens()->delete();   // все сессии прекращаются
            },
        );

        abort_unless($status === Password::PasswordReset, 422, 'Ссылка недействительна или истекла.');

        return response()->json(['data' => ['message' => 'Пароль изменён.']]);
    }
}

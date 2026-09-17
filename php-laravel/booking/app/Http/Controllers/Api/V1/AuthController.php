<?php
// app/Http/Controllers/Api/V1/AuthController.php
declare(strict_types=1);

namespace App\Http\Controllers\Api\V1;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Http\Requests\LoginRequest;
use App\Http\Requests\RegisterRequest;
use App\Http\Resources\UserResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Validation\ValidationException;

final class AuthController extends Controller
{
    public function register(RegisterRequest $request): JsonResponse
    {
        $user = User::create($request->validated());

        return response()->json([
            'data' => new UserResource($user),
            'token' => $user->createToken(
                name: $request->userAgent() ?? 'api',
                abilities: $this->abilitiesFor($user->role),
                expiresAt: now()->addDays(30),
            )->plainTextToken,
        ], Response::HTTP_CREATED);
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $key = 'login:' . $request->string('email')->lower() . '|' . $request->ip();

        if (RateLimiter::tooManyAttempts($key, maxAttempts: 5)) {
            throw ValidationException::withMessages([
                'email' => "Слишком много попыток. Повторите через " .
                    RateLimiter::availableIn($key) . " с.",
            ])->status(Response::HTTP_TOO_MANY_REQUESTS);
        }

        if (! Auth::validate($request->validated())) {
            RateLimiter::hit($key, decaySeconds: 300);

            throw ValidationException::withMessages([
                'email' => 'Неверный адрес или пароль.',
            ]);
        }

        RateLimiter::clear($key);

        $user = User::where('email', $request->string('email'))->firstOrFail();

        // при входе отзываем токены старше 30 дней
        $user->tokens()->where('created_at', '<', now()->subDays(30))->delete();

        return response()->json([
            'data' => new UserResource($user),
            'token' => $user->createToken(
                name: $request->userAgent() ?? 'api',
                abilities: $this->abilitiesFor($user->role),
                expiresAt: now()->addDays(30),
            )->plainTextToken,
        ]);
    }

    public function logout(Request $request): Response
    {
        $request->user()->currentAccessToken()->delete();

        return response()->noContent();
    }

    public function logoutAll(Request $request): Response
    {
        $request->user()->tokens()->delete();

        return response()->noContent();
    }

    /** @return list<string> */
    private function abilitiesFor(Role $role): array
    {
        return match ($role) {
            Role::Participant => ['bookings:manage'],
            Role::Organizer => ['bookings:manage', 'events:manage'],
            Role::Admin => ['*'],
        };
    }
}

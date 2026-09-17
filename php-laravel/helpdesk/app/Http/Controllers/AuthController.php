<?php

declare(strict_types=1);

namespace App\Http\Controllers;

use App\Http\Requests\LoginRequest;
use App\Http\Requests\RegisterRequest;
use App\Http\Resources\UserResource;
use App\Services\AuthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Response;

final class AuthController extends Controller
{
    public function __construct(private readonly AuthService $auth)
    {
    }

    public function register(RegisterRequest $request): JsonResponse
    {
        $result = $this->auth->register($request->validated());

        return response()->json([
            'data' => [
                'user' => UserResource::make($result->user),
                'token' => $result->token,
            ],
        ], 201);
    }

    public function login(LoginRequest $request): JsonResponse
    {
        $result = $this->auth->login(
            $request->string('email')->toString(),
            $request->string('password')->toString(),
            $request->device(),
        );

        return response()->json([
            'data' => [
                'user' => UserResource::make($result->user),
                'token' => $result->token,
            ],
        ], 201);
    }

    public function me(Request $request): JsonResponse
    {
        return $this->ok(UserResource::make($request->user()));
    }

    public function logout(Request $request): Response
    {
        // удаляем только текущий токен — другие устройства остаются
        $request->user()->currentAccessToken()->delete();

        return $this->noContent();
    }

    public function logoutAll(Request $request): Response
    {
        $request->user()->tokens()->delete();

        return $this->noContent();
    }

    public function sessions(Request $request): JsonResponse
    {
        $current = $request->user()->currentAccessToken();

        return $this->ok(
            $request->user()->tokens()
                ->latest('last_used_at')
                ->get()
                ->map(fn ($token): array => [
                    'id' => $token->id,
                    'name' => $token->name,
                    'abilities' => $token->abilities,
                    'last_used_at' => $token->last_used_at?->toIso8601String(),
                    'expires_at' => $token->expires_at?->toIso8601String(),
                    'created_at' => $token->created_at->toIso8601String(),
                    'is_current' => $token->id === $current->id,
                ])
        );
    }

    public function refresh(Request $request): JsonResponse
    {
        $user = $request->user();
        $current = $user->currentAccessToken();

        $new = $user->createToken(
            $current->name,
            $current->abilities,
            now()->addMinutes(config('sanctum.expiration')),
        );

        $current->delete();   // старый сразу недействителен

        return response()->json(['data' => ['token' => $new->plainTextToken]], 201);
    }

    public function revoke(Request $request, int $tokenId): Response
    {
        $deleted = $request->user()->tokens()->whereKey($tokenId)->delete();

        abort_if($deleted === 0, 404, 'Токен не найден.');

        return $this->noContent();
    }
}

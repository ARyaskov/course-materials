<?php

declare(strict_types=1);

namespace App\Api\Auth;

use App\Api\Middleware\AuthMiddleware;
use App\Domain\Auth\TokenClaims;
use App\Domain\User\{User, UserId, UserRepositoryInterface, UserRole};
use Yiisoft\RequestProvider\RequestProviderInterface;

final class CurrentUser
{
    private ?User $loaded = null;

    public function __construct(
        private readonly RequestProviderInterface $requestProvider,
        private readonly UserRepositoryInterface $users,
    ) {
    }

    public function claims(): TokenClaims
    {
        $claims = $this->requestProvider->get()->getAttribute(AuthMiddleware::CLAIMS);

        return $claims instanceof TokenClaims
            ? $claims
            : throw new \LogicException('Запрос не прошёл AuthMiddleware.');
    }

    public function id(): UserId
    {
        return UserId::fromInt($this->claims()->userId);
    }

    public function role(): UserRole
    {
        return $this->claims()->role;
    }

    public function hasPermission(string $permission): bool
    {
        return in_array($permission, $this->claims()->permissions, true);
    }

    /** Полная сущность — только по требованию, и не чаще одного раза за запрос. */
    public function entity(): User
    {
        return $this->loaded ??= $this->users->getById($this->id());
    }
}

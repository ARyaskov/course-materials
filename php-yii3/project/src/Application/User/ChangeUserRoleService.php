<?php

declare(strict_types=1);

namespace App\Application\User;

use App\Api\Auth\{AccessChecker, CurrentUser};
use App\Domain\Shared\Exception\AccessDeniedException;
use App\Domain\User\{Permission, User, UserId, UserRepositoryInterface, UserRole};
use Psr\EventDispatcher\EventDispatcherInterface;

final readonly class ChangeUserRoleService
{
    public function __construct(
        private UserRepositoryInterface $users,
        private AccessChecker $access,
        private CurrentUser $currentUser,
        private EventDispatcherInterface $events,
    ) {
    }

    public function changeRole(UserId $targetId, UserRole $newRole): User
    {
        $this->access->assertCan(Permission::USER_MANAGE);

        // нельзя понизить себя и остаться без администраторов
        if ($targetId->equals($this->currentUser->id()) && $newRole !== UserRole::Admin) {
            throw AccessDeniedException::cannotDemoteSelf();
        }

        $user = $this->users->getById($targetId);
        $user->changeRole($newRole, $this->currentUser->id());
        $this->users->save($user);

        foreach ($user->releaseEvents() as $event) {
            $this->events->dispatch($event);
        }

        return $user;
    }
}

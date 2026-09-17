<?php

declare(strict_types=1);

namespace App\Application\User;

use App\Domain\User\Exception\EmailAlreadyTakenException;
use App\Domain\User\{PasswordHasherInterface, User, UserRepositoryInterface, UserRole};
use Psr\EventDispatcher\EventDispatcherInterface;
use Yiisoft\Db\Exception\IntegrityException;

final readonly class RegisterUserService
{
    public function __construct(
        private UserRepositoryInterface $users,
        private PasswordHasherInterface $hasher,
        private EventDispatcherInterface $events,
    ) {
    }

    public function register(RegisterUserCommand $command): User
    {
        $email = mb_strtolower(trim($command->email));

        // 1. проверка ради понятного сообщения
        if ($this->users->findByEmail($email) !== null) {
            throw EmailAlreadyTakenException::withEmail($email);
        }

        $user = User::register(
            email: $email,
            name: $command->name,
            passwordHash: $this->hasher->hash($command->plainPassword),
            role: UserRole::Reporter,
        );

        try {
            $this->users->save($user);
        } catch (IntegrityException $e) {
            // 2. ограничение UNIQUE ловит гонку, которую проверка выше пропустила
            throw EmailAlreadyTakenException::withEmail($email, previous: $e);
        }

        foreach ($user->releaseEvents() as $event) {
            $this->events->dispatch($event);
        }

        return $user;
    }
}

<?php

declare(strict_types=1);

namespace App\Application\Auth;

use App\Domain\User\Exception\{InvalidCredentialsException, UserIsLockedException};
use App\Domain\User\{PasswordHasherInterface, User, UserRepositoryInterface};
use Psr\Log\LoggerInterface;

final readonly class AuthenticateUserService
{
    public function __construct(
        private UserRepositoryInterface $users,
        private PasswordHasherInterface $hasher,
        private LoggerInterface $logger,
    ) {
    }

    /** @throws InvalidCredentialsException|UserIsLockedException */
    public function authenticate(string $email, string $plainPassword): User
    {
        $now = new \DateTimeImmutable();
        $user = $this->users->findByEmail(mb_strtolower(trim($email)));

        if ($user === null) {
            // хешируем впустую: время ответа не должно выдавать,
            // существует ли пользователь
            $this->hasher->verify($plainPassword, self::DUMMY_HASH);

            throw InvalidCredentialsException::create();
        }

        $user->assertNotLocked($now);

        if (!$user->passwordMatches($this->hasher, $plainPassword)) {
            $user->registerFailedLogin($now);
            $this->users->save($user);

            $this->logger->warning('Неудачная попытка входа', [
                'userId' => $user->id->value,
                'attempts' => $user->failedAttempts,
            ]);

            throw InvalidCredentialsException::create();
        }

        // алгоритм или его параметры изменились — пересчитываем прозрачно
        if ($this->hasher->needsRehash($user->passwordHashForStorage())) {
            $user->changePassword($this->hasher->hash($plainPassword));
        }

        $user->registerSuccessfulLogin();
        $this->users->save($user);

        return $user;
    }

    /** Заранее вычисленный хеш несуществующего пароля. */
    private const DUMMY_HASH = '$argon2id$v=19$m=65536,t=4,p=2$'
        . 'ZHVtbXlzYWx0dmFsdWU$0000000000000000000000000000000000000000000';
}

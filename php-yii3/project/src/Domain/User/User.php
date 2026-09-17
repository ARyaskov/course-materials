<?php

declare(strict_types=1);

namespace App\Domain\User;

use App\Domain\User\Exception\UserIsLockedException;

final class User
{
    private const MAX_FAILED_ATTEMPTS = 5;
    private const LOCK_MINUTES = 15;

    /** @var list<object> */
    private array $events = [];

    private function __construct(
        public private(set) UserId $id,
        public private(set) string $email,
        public private(set) string $name,
        public private(set) UserRole $role,
        // хеш никогда не покидает домен: нет геттера, нет в представлениях
        private string $passwordHash,
        public private(set) int $failedAttempts,
        public private(set) ?\DateTimeImmutable $lockedUntil,
        public readonly \DateTimeImmutable $createdAt,
    ) {
    }

    public static function register(
        string $email,
        string $name,
        string $passwordHash,
        UserRole $role = UserRole::Reporter,
    ): self {
        $user = new self(
            id: UserId::next(),
            // нормализация здесь, а не в каждом месте сравнения
            email: mb_strtolower(trim($email)),
            name: trim($name),
            role: $role,
            passwordHash: $passwordHash,
            failedAttempts: 0,
            lockedUntil: null,
            createdAt: new \DateTimeImmutable(),
        );

        $user->events[] = new Event\UserRegistered($user->id, $user->email);

        return $user;
    }

    /** @throws UserIsLockedException */
    public function assertNotLocked(\DateTimeImmutable $now): void
    {
        if ($this->lockedUntil !== null && $this->lockedUntil > $now) {
            throw UserIsLockedException::until($this->lockedUntil);
        }
    }

    /** Сравнение выполняет проверяющий сервис — домен знает только исход. */
    public function passwordMatches(PasswordHasherInterface $hasher, string $plain): bool
    {
        return $hasher->verify($plain, $this->passwordHash);
    }

    public function registerSuccessfulLogin(): void
    {
        $this->failedAttempts = 0;
        $this->lockedUntil = null;
    }

    public function registerFailedLogin(\DateTimeImmutable $now): void
    {
        $this->failedAttempts++;

        if ($this->failedAttempts >= self::MAX_FAILED_ATTEMPTS) {
            $this->lockedUntil = $now->modify('+' . self::LOCK_MINUTES . ' minutes');
            $this->events[] = new Event\UserLocked($this->id, $this->lockedUntil);
        }
    }

    public function changePassword(string $newHash): void
    {
        $this->passwordHash = $newHash;
        $this->failedAttempts = 0;
        $this->lockedUntil = null;

        // отзыв всех сессий — часть смены пароля, а не отдельное действие
        $this->events[] = new Event\PasswordChanged($this->id, new \DateTimeImmutable());
    }

    /** Только для репозитория: единственный способ достать хеш наружу. */
    public function passwordHashForStorage(): string
    {
        return $this->passwordHash;
    }

    /** @return list<object> */
    public function releaseEvents(): array
    {
        $events = $this->events;
        $this->events = [];

        return $events;
    }

    public function changeRole(UserRole $newRole, UserId $actorId): void
    {
    if ($this->role === $newRole) {
        return;
    }

    $previous = $this->role;
    $this->role = $newRole;

    // смена роли — событие безопасности: она должна быть видна в аудите
    $this->events[] = new Event\RoleChanged($this->id, $previous, $newRole, $actorId);
    }
}

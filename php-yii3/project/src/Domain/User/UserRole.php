<?php

declare(strict_types=1);

namespace App\Domain\User;

enum UserRole: string
{
    case Admin = 'admin';
    case Agent = 'agent';
    case Reporter = 'reporter';

    /**
     * Права роли перечислены явно. Строки — константы,
     * а не «магические» литералы по коду.
     * @return list<string>
     */
    public function permissions(): array
    {
        return match ($this) {
            self::Admin => [
                Permission::TICKET_VIEW_ANY,
                Permission::TICKET_CREATE,
                Permission::TICKET_UPDATE_ANY,
                Permission::TICKET_ASSIGN,
                Permission::TICKET_DELETE,
                Permission::USER_MANAGE,
                Permission::REPORT_VIEW,
            ],
            self::Agent => [
                Permission::TICKET_VIEW_ANY,
                Permission::TICKET_CREATE,
                Permission::TICKET_UPDATE_ANY,
                Permission::TICKET_ASSIGN,
                Permission::REPORT_VIEW,
            ],
            self::Reporter => [
                Permission::TICKET_VIEW_OWN,
                Permission::TICKET_CREATE,
                Permission::TICKET_UPDATE_OWN,
            ],
        };
    }

    public function has(string $permission): bool
    {
        return in_array($permission, $this->permissions(), true);
    }

    public function label(): string
    {
        return match ($this) {
            self::Admin => 'Администратор',
            self::Agent => 'Сотрудник поддержки',
            self::Reporter => 'Заявитель',
        };
    }
}

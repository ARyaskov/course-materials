<?php
// app/Enums/TokenAbility.php
declare(strict_types=1);

namespace App\Enums;

enum TokenAbility: string
{
    case TicketsRead = 'tickets:read';
    case TicketsWrite = 'tickets:write';
    case TicketsDelete = 'tickets:delete';
    case CommentsWrite = 'comments:write';
    case StatsRead = 'stats:read';

    /** @return list<string> */
    public static function forRole(UserRole $role): array
    {
        return match ($role) {
            UserRole::Admin => ['*'],
            UserRole::Agent => [
                self::TicketsRead->value, self::TicketsWrite->value,
                self::TicketsDelete->value, self::CommentsWrite->value, self::StatsRead->value,
            ],
            UserRole::User => [
                self::TicketsRead->value, self::TicketsWrite->value, self::CommentsWrite->value,
            ],
        };
    }
}

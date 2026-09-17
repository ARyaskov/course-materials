<?php
// app/Enums/Role.php
declare(strict_types=1);

namespace App\Enums;

enum Role: string
{
    case Participant = 'participant';
    case Organizer = 'organizer';
    case Admin = 'admin';

    public function label(): string
    {
        return match ($this) {
            self::Participant => 'Участник',
            self::Organizer => 'Организатор',
            self::Admin => 'Администратор',
        };
    }

    public function canPublishEvents(): bool
    {
        return $this !== self::Participant;
    }

    public function canManageAnyEvent(): bool
    {
        return $this === self::Admin;
    }
}

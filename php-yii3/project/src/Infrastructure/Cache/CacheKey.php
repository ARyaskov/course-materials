<?php

declare(strict_types=1);

namespace App\Infrastructure\Cache;

use App\Domain\Ticket\TicketFilter;
use App\Domain\Ticket\TicketId;
use App\Domain\User\UserId;

/**
 * Ключи собираются здесь, а не строками по коду: иначе инвалидация
 * промахивается из-за расхождения в один символ.
 */
final class CacheKey
{
    private const PREFIX = 'hd';

    /** Версия схемы данных: смена ломает все старые ключи разом. */
    private const VERSION = 'v2';

    public static function ticket(TicketId $id): string
    {
        return self::build('ticket', (string) $id->value);
    }

    public static function departmentSummary(int $departmentId): string
    {
        return self::build('report', 'summary', (string) $departmentId);
    }

    /** Список зависит от фильтра И от того, кто спрашивает. */
    public static function ticketList(UserId $viewer, TicketFilter $filter): string
    {
        return self::build(
            'tickets', 'list', (string) $viewer->value,
            // хеш от нормализованного фильтра: порядок ключей не влияет
            hash('xxh128', json_encode($filter->toNormalizedArray(), JSON_THROW_ON_ERROR)),
        );
    }

    public static function userPermissions(UserId $id): string
    {
        return self::build('user', 'permissions', (string) $id->value);
    }

    private static function build(string ...$parts): string
    {
        return implode(':', [self::PREFIX, self::VERSION, ...$parts]);
    }
}

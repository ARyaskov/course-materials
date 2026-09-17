<?php
// app/Support/TenantContext.php
declare(strict_types=1);

namespace App\Support;

final class TenantContext
{
    private static ?int $tenantId = null;

    public static function set(int $id): void
    {
        self::$tenantId = $id;
    }

    public static function id(): int
    {
        return self::$tenantId ?? throw new \LogicException('Контекст не установлен');
    }

    public static function forget(): void
    {
        self::$tenantId = null;
    }
}

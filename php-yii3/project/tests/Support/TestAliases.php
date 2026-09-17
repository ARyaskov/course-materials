<?php

declare(strict_types=1);

namespace App\Tests\Support;

use Yiisoft\Aliases\Aliases;

final class TestAliases
{
    /** Уникальный каталог на каждый прогон: тесты не пересекаются. */
    public static function create(): Aliases
    {
        $root = sys_get_temp_dir() . '/helpdesk-test-' . bin2hex(random_bytes(6));

        foreach (['/runtime/logs', '/runtime/cache', '/storage/attachments'] as $sub) {
            mkdir($root . $sub, 0o775, true);
        }

        return new Aliases([
            '@root' => dirname(__DIR__, 2),
            '@runtime' => $root . '/runtime',
            '@storage' => $root . '/storage',
            '@logs' => '@runtime/logs',
            '@attachments' => '@storage/attachments',
            '@web' => 'http://helpdesk.test',
        ]);
    }
}

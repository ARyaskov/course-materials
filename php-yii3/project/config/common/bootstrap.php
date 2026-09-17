<?php

declare(strict_types=1);

use Psr\Container\ContainerInterface;
use Yiisoft\Aliases\Aliases;

return [
    static function (ContainerInterface $container): void {
        // единая временная зона: иначе форматирование дат зависит от php.ini хоста
        date_default_timezone_set('UTC');

        // строгий режим для JSON: битая кодировка станет исключением, а не тихим false
        ini_set('serialize_precision', '-1');

        $aliases = $container->get(Aliases::class);

        foreach (['@runtime/logs', '@runtime/cache', '@storage/attachments'] as $alias) {
            $path = $aliases->get($alias);

            if (!is_dir($path) && !mkdir($path, 0o775, true) && !is_dir($path)) {
                throw new \RuntimeException("Не удалось создать каталог: {$path}");
            }
        }
    },
];

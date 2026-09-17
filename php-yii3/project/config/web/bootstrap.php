<?php

declare(strict_types=1);

use Psr\Container\ContainerInterface;

return [
    static function (ContainerInterface $container): void {
        // заголовок с версией PHP не должен уходить клиенту
        header_remove('X-Powered-By');
    },
];

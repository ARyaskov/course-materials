<?php

declare(strict_types=1);

use App\Api\Auth\CurrentUser;
use App\Console\SystemUser;

return [
    // в консоли CurrentUser подменяется реализацией без запроса
    CurrentUser::class => SystemUser::class,
];

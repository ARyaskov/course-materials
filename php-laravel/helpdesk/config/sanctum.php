<?php
// config/sanctum.php
declare(strict_types=1);

return [
    'expiration' => (int) env('SANCTUM_EXPIRATION', 60 * 24 * 30),   // минут; null — бессрочно
    'token_prefix' => env('SANCTUM_TOKEN_PREFIX', 'hd_'),
];

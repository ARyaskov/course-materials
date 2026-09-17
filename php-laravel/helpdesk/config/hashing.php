<?php
// config/hashing.php
declare(strict_types=1);

return [
    'driver' => env('HASH_DRIVER', 'argon2id'),

    'bcrypt' => [
        'rounds' => (int) env('BCRYPT_ROUNDS', 12),
        'verify' => true,
    ],

    'argon' => [
        'memory' => (int) env('ARGON_MEMORY', 65536),   // 64 МБ
        'threads' => (int) env('ARGON_THREADS', 3),
        'time'    => (int) env('ARGON_TIME', 4),
        'verify'  => true,
    ],
];

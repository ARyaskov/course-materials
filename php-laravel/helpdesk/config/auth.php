<?php
// config/auth.php
declare(strict_types=1);

return [
    'defaults' => ['guard' => 'sanctum', 'passwords' => 'users'],

    'guards' => [
        'web' => [
            'driver'   => 'session',
            'provider' => 'users',
        ],
        'sanctum' => [
            'driver'   => 'sanctum',
            'provider' => 'users',
        ],
    ],

    'providers' => [
        'users' => [
            'driver' => 'eloquent',
            'model'  => App\Models\User::class,
        ],
    ],
];

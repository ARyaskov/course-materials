<?php
// config/filesystems.php
declare(strict_types=1);

return [
    'default' => env('FILESYSTEM_DISK', 'private'),

    'disks' => [
        // приватный: недоступен по HTTP, отдаётся только через контроллер
        'private' => [
            'driver' => 'local',
            'root'   => storage_path('app/private'),
            'throw'  => true,
        ],

        // публичный: доступен по ссылке через symlink public/storage
        'public' => [
            'driver'     => 'local',
            'root'       => storage_path('app/public'),
            'url'        => env('APP_URL') . '/storage',
            'visibility' => 'public',
            'throw'      => true,
        ],

        // объектное хранилище, совместимое с S3
        's3' => [
            'driver'                  => 's3',
            'key'                     => env('AWS_ACCESS_KEY_ID'),
            'secret'                  => env('AWS_SECRET_ACCESS_KEY'),
            'region'                  => env('AWS_DEFAULT_REGION', 'ru-central1'),
            'bucket'                  => env('AWS_BUCKET'),
            'endpoint'                => env('AWS_ENDPOINT'),
            'use_path_style_endpoint' => (bool) env('AWS_USE_PATH_STYLE_ENDPOINT', true),
            'visibility'              => 'private',
            'throw'                   => true,
        ],
    ],

    'links' => [
        public_path('storage') => storage_path('app/public'),
    ],
];

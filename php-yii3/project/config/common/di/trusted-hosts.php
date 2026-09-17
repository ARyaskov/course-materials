<?php

declare(strict_types=1);

use Yiisoft\Yii\Middleware\TrustedHostsNetworkResolver;

return [
    TrustedHostsNetworkResolver::class => [
        'class' => TrustedHostsNetworkResolver::class,
        'withTrustedHosts()' => [
            // подсеть docker-сети, где живёт nginx
            'hosts' => ['172.16.0.0/12', '10.0.0.0/8'],
            'ipHeaders' => ['x-forwarded-for'],
            'protocolHeaders' => ['x-forwarded-proto' => ['http', 'https']],
        ],
    ],
];

<?php

declare(strict_types=1);

namespace App\Tests\Functional\Api;

use App\Tests\Support\ApiTestCase;
use PHPUnit\Framework\Attributes\Test;
use Yiisoft\Router\RouteCollectionInterface;

final class RouteProtectionTest extends ApiTestCase
{
    /** Маршруты, доступные без токена. Список расширяется осознанно. */
    private const PUBLIC_ROUTES = [
        'api/v1/health',
        'api/v1/version',
        'api/v1/auth/login',
        'api/v1/auth/refresh',
    ];

    #[Test]
    public function все_маршруты_кроме_публичных_требуют_токен(): void
    {
        $routes = $this->container->get(RouteCollectionInterface::class)->getRoutes();
        $unprotected = [];

        foreach ($routes as $route) {
            $name = $route->getData('name');

            if (in_array($name, self::PUBLIC_ROUTES, true)) {
                continue;
            }

            $response = $this->request(
                $route->getData('methods')[0],
                $this->fillRouteParams($route->getData('pattern')),
                null,
                [],                                  // без заголовка Authorization
            );

            if ($response->getStatusCode() !== 401) {
                $unprotected[] = $name . ' → ' . $response->getStatusCode();
            }
        }

        self::assertSame([], $unprotected,
            'Маршруты доступны без аутентификации: ' . implode(', ', $unprotected));
    }
}

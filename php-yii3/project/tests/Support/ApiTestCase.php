<?php

declare(strict_types=1);

namespace App\Tests\Support;

use HttpSoft\Message\{ServerRequest, StreamFactory};
use PHPUnit\Framework\TestCase;
use Psr\Container\ContainerInterface;
use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Yiisoft\Config\{Config, ConfigPaths};
use Yiisoft\Di\{Container, ContainerConfig};
use Yiisoft\Yii\Http\Application;

abstract class ApiTestCase extends TestCase
{
    protected ContainerInterface $container;

    protected DatabaseFixture $fixture;

    protected function setUp(): void
    {
        parent::setUp();

        $this->container = $this->buildContainer();
        $this->fixture = new DatabaseFixture($this->container->get(ConnectionInterface::class));

        // чистая база перед каждым тестом: порядок выполнения случаен,
        // и тесты не должны зависеть друг от друга
        $this->fixture->truncateAll();
    }

    /** Прогон запроса через ВЕСЬ конвейер: middleware, роутер, обработчик. */
    protected function request(
        string $method,
        string $path,
        array|string|null $body = null,
        array $headers = [],
    ): ResponseInterface {
        $request = new ServerRequest(method: $method, uri: $path);

        foreach ($headers as $name => $value) {
            $request = $request->withHeader($name, $value);
        }

        if ($body !== null) {
            $encoded = is_string($body) ? $body : json_encode($body, JSON_THROW_ON_ERROR);

            $request = $request
                ->withHeader('Content-Type', 'application/json')
                ->withBody((new StreamFactory())->createStream($encoded));
        }

        return $this->container->get(Application::class)->handle($request);
    }

    // get(), post(), patch(), delete() — обёртки над request();
    // json() разбирает тело; headersFor('agent') выдаёт токен нужной роли
    // без реального входа через /auth/login.

    private function buildContainer(): ContainerInterface
    {
        $config = new Config(new ConfigPaths(dirname(__DIR__, 2), 'config'), 'test');

        return new Container(
            ContainerConfig::create()->withDefinitions($config->get('di-web')),
        );
    }
}

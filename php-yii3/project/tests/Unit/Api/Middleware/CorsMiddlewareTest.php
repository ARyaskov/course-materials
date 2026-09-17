<?php

declare(strict_types=1);

namespace App\Tests\Unit\Api\Middleware;

use App\Api\Middleware\CorsMiddleware;
use App\Tests\Support\SpyHandler;
use HttpSoft\Message\ResponseFactory;
use HttpSoft\Message\ServerRequest;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class CorsMiddlewareTest extends TestCase
{
    #[Test]
    public function предзапрос_не_доходит_до_следующего_слоя(): void
    {
        $handler = new SpyHandler();

        $request = (new ServerRequest(method: 'OPTIONS'))
            ->withHeader('Origin', 'https://helpdesk.example')
            ->withHeader('Access-Control-Request-Method', 'POST');

        $response = $this->middleware()->process($request, $handler);

        self::assertSame(204, $response->getStatusCode());
        self::assertFalse($handler->wasCalled(), 'предзапрос должен обрываться на CORS');
        self::assertSame('https://helpdesk.example',
            $response->getHeaderLine('Access-Control-Allow-Origin'));
        self::assertSame('600', $response->getHeaderLine('Access-Control-Max-Age'));
    }

    #[Test]
    public function обычный_запрос_проходит_и_получает_заголовки(): void
    {
        $handler = new SpyHandler();

        $request = (new ServerRequest())->withHeader('Origin', 'https://helpdesk.example');

        $response = $this->middleware()->process($request, $handler);

        self::assertTrue($handler->wasCalled());
        self::assertSame('https://helpdesk.example',
            $response->getHeaderLine('Access-Control-Allow-Origin'));
        self::assertSame('Origin', $response->getHeaderLine('Vary'));
    }

    #[Test]
    public function чужой_источник_не_получает_разрешения(): void
    {
        $request = (new ServerRequest())->withHeader('Origin', 'https://evil.example');

        $response = $this->middleware()->process($request, new SpyHandler());

        self::assertSame('', $response->getHeaderLine('Access-Control-Allow-Origin'));
        self::assertSame('Origin', $response->getHeaderLine('Vary'));
    }

    private function middleware(): CorsMiddleware
    {
        return new CorsMiddleware(
            new ResponseFactory(),
            ['https://helpdesk.example'],
        );
    }
}

<?php

declare(strict_types=1);

namespace App\Tests\Unit\Api\Middleware;

use App\Api\Middleware\AuthMiddleware;
use App\Domain\Auth\Exception\TokenExpiredException;
use App\Tests\Support\{SpyHandler, StubAccessTokenService};
use HttpSoft\Message\ServerRequest;
use PHPUnit\Framework\Attributes\Test;
use PHPUnit\Framework\TestCase;

final class AuthMiddlewareTest extends TestCase
{
    #[Test]
    public function без_заголовка_возвращает_401_и_не_вызывает_следующий_слой(): void
    {
        $handler = new SpyHandler();

        $response = $this->middleware()->process(new ServerRequest(), $handler);

        self::assertSame(401, $response->getStatusCode());
        self::assertFalse($handler->wasCalled());
        self::assertStringContainsString('Bearer', $response->getHeaderLine('WWW-Authenticate'));
    }

    #[Test]
    public function истёкший_токен_даёт_отдельный_тип_ошибки(): void
    {
        $tokens = new StubAccessTokenService();
        $tokens->willThrow(TokenExpiredException::at(new \DateTimeImmutable('-1 hour')));

        $request = (new ServerRequest())->withHeader('Authorization', 'Bearer expired');

        $response = $this->middleware($tokens)->process($request, new SpyHandler());

        self::assertSame(401, $response->getStatusCode());
        self::assertSame('token_expired', $this->json($response)['error']['type']);
    }

    #[Test]
    public function кладёт_claims_и_userId_в_атрибуты(): void
    {
        $handler = new SpyHandler();
        $request = (new ServerRequest())->withHeader('Authorization', 'bearer valid');

        $this->middleware()->process($request, $handler);

        $seen = $handler->receivedRequest();

        self::assertSame(42, $seen?->getAttribute(AuthMiddleware::USER_ID));
        self::assertNotNull($seen?->getAttribute(AuthMiddleware::CLAIMS));
    }

    public function прерывает_цепочку_без_заголовка_authorization(): void
    {
        $nextCalled = false;

        $handler = $this->handlerThatSets($nextCalled);

        $response = $this->createMiddleware()
            ->process(new ServerRequest(), $handler);

        self::assertSame(401, $response->getStatusCode());
        self::assertFalse($nextCalled, 'следующий слой не должен был выполниться');
        self::assertStringContainsString('Bearer', $response->getHeaderLine('WWW-Authenticate'));
    }

    #[Test]
    public function кладёт_userId_в_атрибут_запроса(): void
    {
        $seenUserId = null;

        $handler = new class ($seenUserId) implements RequestHandlerInterface {
            public function __construct(private mixed &$seen)
            {
            }

            public function handle(ServerRequestInterface $request): ResponseInterface
            {
                $this->seen = $request->getAttribute(AuthMiddleware::USER_ID);

                return new Response(200);
            }
        };

        $request = (new ServerRequest())->withHeader('Authorization', 'Bearer valid-token');

        $this->createMiddleware()->process($request, $handler);

        self::assertSame(42, $seenUserId);
    }
}

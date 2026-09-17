<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\Http\Method;

final readonly class CacheHeadersMiddleware implements MiddlewareInterface
{
    public function __construct(private int $maxAge = 60)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $response = $handler->handle($request);

        // кешировать можно только успешные ответы на безопасные методы
        $cacheable = $request->getMethod() === Method::GET
            && $response->getStatusCode() === 200;

        return $cacheable
            ? $response->withHeader('Cache-Control', "public, max-age={$this->maxAge}")
            : $response->withHeader('Cache-Control', 'no-store');
    }
}

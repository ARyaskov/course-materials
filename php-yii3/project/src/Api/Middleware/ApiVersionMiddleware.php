<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;

final readonly class ApiVersionMiddleware implements MiddlewareInterface
{
    public const ATTRIBUTE = 'apiVersion';

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        $path = $request->getUri()->getPath();

        $version = preg_match('#^/api/(v\d+)/#', $path, $m) === 1 ? $m[1] : 'unknown';

        return $handler
            ->handle($request->withAttribute(self::ATTRIBUTE, $version))
            ->withHeader('X-API-Version', $version);
    }
}

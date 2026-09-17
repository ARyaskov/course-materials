<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Psr\Http\Server\{MiddlewareInterface, RequestHandlerInterface};

final readonly class SecurityHeadersMiddleware implements MiddlewareInterface
{
    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        return $handler->handle($request)
            // без этого браузер «угадывает» тип и может счесть JSON разметкой
            ->withHeader('X-Content-Type-Options', 'nosniff')
            // ответ API не должен открываться во фрейме
            ->withHeader('X-Frame-Options', 'DENY')
            // API не отдаёт разметку — запрещаем всё
            ->withHeader('Content-Security-Policy',
                "default-src 'none'; frame-ancestors 'none'; base-uri 'none'")
            ->withHeader('Referrer-Policy', 'no-referrer');
    }
}

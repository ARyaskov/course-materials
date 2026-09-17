<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseFactoryInterface;
use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\Http\Method;
use Yiisoft\Http\Status;

/**
 * Условные запросы для карточек: урок 17.2 показывает расчёт ETag
 * и короткое замыкание на 304.
 */
final readonly class ETagMiddleware implements MiddlewareInterface
{
    public function __construct(private ResponseFactoryInterface $responseFactory)
    {
    }

    public function process(ServerRequestInterface $request, RequestHandlerInterface $handler): ResponseInterface
    {
        $response = $handler->handle($request);

        if ($request->getMethod() !== Method::GET || $response->getStatusCode() !== Status::OK) {
            return $response;
        }

        $etag = '"' . hash('xxh128', (string) $response->getBody()) . '"';

        if (in_array($etag, $this->parseIfNoneMatch($request), true)) {
            return $this->responseFactory
                ->createResponse(Status::NOT_MODIFIED)
                ->withHeader('ETag', $etag)
                // private: ответ содержит данные конкретного пользователя
                ->withHeader('Cache-Control', 'private, max-age=30');
        }

        return $response
            ->withHeader('ETag', $etag)
            ->withHeader('Cache-Control', 'private, max-age=30');
    }

    /** @return list<string> */
    private function parseIfNoneMatch(ServerRequestInterface $request): array
    {
        $header = $request->getHeaderLine('If-None-Match');

        if ($header === '') {
            return [];
        }

        return array_values(array_filter(array_map(trim(...), explode(',', $header))));
    }
}

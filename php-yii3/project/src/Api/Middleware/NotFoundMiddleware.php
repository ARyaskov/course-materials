<?php

declare(strict_types=1);

namespace App\Api\Middleware;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Psr\Http\Server\MiddlewareInterface;
use Psr\Http\Server\RequestHandlerInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;

final readonly class NotFoundMiddleware implements MiddlewareInterface
{
    public function __construct(private DataResponseFactoryInterface $responseFactory)
    {
    }

    public function process(
        ServerRequestInterface $request,
        RequestHandlerInterface $handler,
    ): ResponseInterface {
        return $this->responseFactory->createResponse([
            'error' => [
                'type' => 'not_found',
                'message' => sprintf(
                    'Маршрут %s %s не существует.',
                    $request->getMethod(),
                    $request->getUri()->getPath(),
                ),
            ],
        ], Status::NOT_FOUND);
    }
}

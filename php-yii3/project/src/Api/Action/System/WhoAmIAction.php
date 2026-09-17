<?php

declare(strict_types=1);

namespace App\Api\Action\System;

use Psr\Http\Message\ResponseInterface;
use Psr\Http\Message\ServerRequestInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;

final readonly class WhoAmIAction
{
    public function __construct(
        private DataResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(ServerRequestInterface $request): ResponseInterface
    {
        $uri = $request->getUri();

        return $this->responseFactory->createResponse([
            'scheme' => $uri->getScheme(),          // https, если прокси настроен верно
            'host' => $uri->getHost(),
            'clientIp' => $request->getAttribute('requestClientIp'),
            'method' => $request->getMethod(),
            'headers' => array_keys($request->getHeaders()),
        ]);
    }
}

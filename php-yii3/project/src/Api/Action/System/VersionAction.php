<?php

declare(strict_types=1);

namespace App\Api\Action\System;

use Psr\Http\Message\ResponseInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;

final readonly class VersionAction
{
    public function __construct(
        private DataResponseFactoryInterface $responseFactory,
        private string $version,          // из params: getenv('APP_VERSION')
    ) {
    }

    public function __invoke(): ResponseInterface
    {
        return $this->responseFactory->createResponse([
            'version' => $this->version,
            'php' => PHP_VERSION,
        ]);
    }
}

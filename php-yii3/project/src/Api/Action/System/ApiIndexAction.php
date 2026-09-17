<?php

declare(strict_types=1);

namespace App\Api\Action\System;

use Psr\Http\Message\ResponseInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Router\UrlGeneratorInterface;

final readonly class ApiIndexAction
{
    public function __construct(
        private DataResponseFactoryInterface $responseFactory,
        private UrlGeneratorInterface $urlGenerator,
    ) {
    }

    public function __invoke(): ResponseInterface
    {
        return $this->responseFactory->createResponse([
            'versions' => [
                [
                    'version' => 'v1',
                    'status' => 'deprecated',
                    'sunset' => '2027-03-01',
                    'url' => $this->urlGenerator->generate('api/v1/tickets/index'),
                ],
                [
                    'version' => 'v2',
                    'status' => 'current',
                    'sunset' => null,
                    'url' => $this->urlGenerator->generate('api/v2/tickets/index'),
                ],
            ],
        ]);
    }
}

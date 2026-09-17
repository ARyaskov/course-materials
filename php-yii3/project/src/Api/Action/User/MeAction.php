<?php

declare(strict_types=1);

namespace App\Api\Action\User;

use App\Api\Auth\CurrentUser;
use Psr\Http\Message\ResponseInterface;
use Yiisoft\DataResponse\DataResponseFactoryInterface;

final readonly class MeAction
{
    public function __construct(
        private CurrentUser $currentUser,
        private DataResponseFactoryInterface $responseFactory,
    ) {
    }

    public function __invoke(): ResponseInterface
    {
        $claims = $this->currentUser->claims();

        return $this->responseFactory->createResponse([
            'id' => $claims->userId,
            'email' => $claims->email,
            'role' => $claims->role->value,
            'roleLabel' => $claims->role->label(),
            // клиент нарисует интерфейс по этому списку —
            // но каждая операция всё равно проверяется на сервере
            'permissions' => $claims->permissions,
        ]);
    }
}

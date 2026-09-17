<?php

declare(strict_types=1);

namespace App\Api\Error;

use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Http\Status;
use Psr\Http\Message\ResponseInterface;
use Yiisoft\Validator\Result;

final readonly class ValidationErrorResponder
{
    public function __construct(private DataResponseFactoryInterface $responseFactory)
    {
    }

    public function fromResult(Result $result): ResponseInterface
    {
        $errors = [];

        foreach ($result->getErrorMessagesIndexedByPath() as $path => $messages) {
            $errors[] = [
                'field' => $path,
                'messages' => array_values($messages),
            ];
        }

        return $this->responseFactory->createResponse([
            'error' => [
                'type' => 'validation_failed',
                'message' => 'Проверьте правильность заполнения полей.',
                'details' => $errors,
            ],
        ], Status::UNPROCESSABLE_ENTITY);
    }

    public function malformedBody(): ResponseInterface
    {
        // 400, а не 422: тело вообще не удалось разобрать
        return $this->responseFactory->createResponse([
            'error' => [
                'type' => 'malformed_body',
                'message' => 'Тело запроса должно быть JSON-объектом.',
            ],
        ], Status::BAD_REQUEST);
    }
}

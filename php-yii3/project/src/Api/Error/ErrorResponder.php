<?php

declare(strict_types=1);

namespace App\Api\Error;

use Psr\Http\Message\{ResponseInterface, ServerRequestInterface};
use Yiisoft\DataResponse\DataResponseFactoryInterface;
use Yiisoft\Validator\Result;

/** Единственное место, где собирается тело ошибки. */
final readonly class ErrorResponder
{
    public function __construct(private DataResponseFactoryInterface $responseFactory)
    {
    }

    /** @param list<array{field: string, messages: list<string>}> $details */
    public function respond(
        ErrorType $type,
        string $message,
        array $details = [],
        ?ServerRequestInterface $request = null,
    ): ResponseInterface {
        $error = ['type' => $type->value, 'message' => $message];

        // пустые поля не включаем: клиенту незачем отличать [] от отсутствия
        if ($details !== []) {
            $error['details'] = $details;
        }

        $requestId = $request?->getAttribute('requestId');

        if (is_string($requestId)) {
            $error['requestId'] = $requestId;
        }

        $response = $this->responseFactory->createResponse(
            ['error' => $error],
            $type->status(),
        );

        // клиент узнаёт о возможности повтора из заголовка, не разбирая тело
        return $type->isRetryable()
            ? $response->withHeader('Retry-After', '30')
            : $response;
    }

    public function fromValidationResult(
        Result $result,
        ?ServerRequestInterface $request = null,
    ): ResponseInterface {
        $details = [];

        // ключ — путь к полю: 'title', 'tags.0', 'contact.email'
        foreach ($result->getErrorMessagesIndexedByPath() as $path => $messages) {
            $details[] = ['field' => $path, 'messages' => array_values($messages)];
        }

        return $this->respond(
            ErrorType::ValidationFailed,
            'Проверьте правильность заполнения полей.',
            $details,
            $request,
        );
    }
}

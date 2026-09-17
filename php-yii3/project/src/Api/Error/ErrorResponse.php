<?php

declare(strict_types=1);

namespace App\Api\Error;

final readonly class ErrorResponse
{
    /** @param list<array{field: string, messages: list<string>}> $details */
    private function __construct(
        public ErrorType $type,
        public string $message,
        public array $details = [],
        public ?string $requestId = null,
    ) {
    }

    public static function of(ErrorType $type, string $message): self
    {
        return new self($type, $message);
    }

    /** @param list<array{field: string, messages: list<string>}> $details */
    public static function withDetails(ErrorType $type, string $message, array $details): self
    {
        return new self($type, $message, $details);
    }

    public function withRequestId(?string $requestId): self
    {
        return new self($this->type, $this->message, $this->details, $requestId);
    }

    /** @return array<string, mixed> */
    public function toArray(): array
    {
        $error = ['type' => $this->type->value, 'message' => $this->message];

        // пустые поля не включаем: клиенту не нужно отличать [] от отсутствия
        if ($this->details !== []) {
            $error['details'] = $this->details;
        }

        if ($this->requestId !== null) {
            $error['requestId'] = $this->requestId;
        }

        return ['error' => $error];
    }
}

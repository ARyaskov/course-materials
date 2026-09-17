<?php

declare(strict_types=1);

namespace App\DTO;

use App\Domain\Money;

final readonly class ChargeResult
{
    public function __construct(
        public string $transactionId,
        public string $status,
        public Money $amount,
        public ?string $failureReason = null,
    ) {
    }

    public function isSuccessful(): bool
    {
        return $this->status === 'succeeded';
    }
}

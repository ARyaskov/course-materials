<?php
// app/Contracts/PaymentGateway.php
declare(strict_types=1);

namespace App\Contracts;

use App\Domain\Money;
use App\DTO\ChargeResult;

interface PaymentGateway
{
    public function charge(Money $amount, string $token, string $idempotencyKey): ChargeResult;

    public function refund(string $transactionId, ?Money $amount = null): ChargeResult;

    public function status(string $transactionId): ChargeResult;
}

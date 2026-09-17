<?php
// app/Casts/MoneyCast.php
declare(strict_types=1);

namespace App\Casts;

use App\Domain\Money;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** @implements CastsAttributes<Money|null, Money|int|null> */
final readonly class MoneyCast implements CastsAttributes
{
    public function __construct(private string $currency = 'RUB')
    {
    }

    public function get(Model $model, string $key, mixed $value, array $attributes): ?Money
    {
        return $value === null ? null : Money::fromMinor((int) $value, $this->currency);
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): ?int
    {
        return match (true) {
            $value === null    => null,
            $value instanceof Money => $value->minor,
            is_int($value)     => $value,
            default => throw new \InvalidArgumentException('Ожидается Money или int'),
        };
    }
}

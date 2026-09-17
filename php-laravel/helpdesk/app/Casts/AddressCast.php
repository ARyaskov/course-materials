<?php
// app/Casts/AddressCast.php
declare(strict_types=1);

namespace App\Casts;

use App\Domain\Address;
use Illuminate\Contracts\Database\Eloquent\CastsAttributes;
use Illuminate\Database\Eloquent\Model;

/** @implements CastsAttributes<Address|null, Address|null> */
final readonly class AddressCast implements CastsAttributes
{
    public function get(Model $model, string $key, mixed $value, array $attributes): ?Address
    {
        if ($attributes['city'] === null) {
            return null;
        }

        return new Address(
            city: $attributes['city'],
            street: $attributes['street'],
            building: $attributes['building'],
        );
    }

    public function set(Model $model, string $key, mixed $value, array $attributes): array
    {
        return [
            'city'     => $value?->city,
            'street'   => $value?->street,
            'building' => $value?->building,
        ];
    }
}

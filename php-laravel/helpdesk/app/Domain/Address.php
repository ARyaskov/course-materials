<?php

declare(strict_types=1);

namespace App\Domain;

final readonly class Address
{
    public function __construct(
        public string $country,
        public string $city,
        public string $street,
        public string $postcode,
    ) {
    }

    /** @param array{country?: string, city?: string, street?: string, postcode?: string} $data */
    public static function fromArray(array $data): self
    {
        return new self(
            country: $data['country'] ?? '',
            city: $data['city'] ?? '',
            street: $data['street'] ?? '',
            postcode: $data['postcode'] ?? '',
        );
    }

    /** @return array<string, string> */
    public function toArray(): array
    {
        return [
            'country' => $this->country,
            'city' => $this->city,
            'street' => $this->street,
            'postcode' => $this->postcode,
        ];
    }
}

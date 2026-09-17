<?php
// app/Domain/Money.php
declare(strict_types=1);

namespace App\Domain;

final readonly class Money
{
    private function __construct(public int $minor, public string $currency)
    {
    }

    public static function fromMinor(int $minor, string $currency = 'RUB'): self
    {
        return new self($minor, $currency);
    }

    public static function fromString(string $amount, string $currency = 'RUB'): self
    {
        return new self((int) round((float) $amount * 100), $currency);
    }

    public function add(self $other): self
    {
        $this->assertSameCurrency($other);

        return new self($this->minor + $other->minor, $this->currency);
    }

    public function multiply(int $factor): self
    {
        return new self($this->minor * $factor, $this->currency);
    }

    public function format(): string
    {
        return number_format($this->minor / 100, 2, ',', ' ') . ' ' . $this->currency;
    }

    private function assertSameCurrency(self $other): void
    {
        if ($other->currency !== $this->currency) {
            throw new \InvalidArgumentException('Валюты не совпадают');
        }
    }
}

$price = Money::fromString('1299.90');
$total = $price->multiply(3)->add(Money::fromMinor(5000));

echo $total->format();   // 3 949,70 RUB

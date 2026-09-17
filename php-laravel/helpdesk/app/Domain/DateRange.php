<?php
// app/Domain/DateRange.php
declare(strict_types=1);

namespace App\Domain;

use DateTimeImmutable;
use InvalidArgumentException;

final readonly class DateRange
{
    public function __construct(
        public DateTimeImmutable $from,
        public DateTimeImmutable $to,
    ) {
        if ($from > $to) {
            throw new InvalidArgumentException('Начало периода позже конца');
        }
    }

    public static function lastDays(int $days): self
    {
        $now = new DateTimeImmutable();

        return new self($now->modify("-{$days} days"), $now);
    }

    public function withTo(DateTimeImmutable $to): self
    {
        return new self($this->from, $to);
    }

    public function extendedBy(int $days): self
    {
        return new self($this->from, $this->to->modify("+{$days} days"));
    }

    public function days(): int
    {
        return (int) $this->from->diff($this->to)->days;
    }

    public function contains(DateTimeImmutable $moment): bool
    {
        return $moment >= $this->from && $moment <= $this->to;
    }

    public function overlaps(self $other): bool
    {
        return $this->from <= $other->to && $other->from <= $this->to;
    }
}

$week = DateRange::lastDays(7);
$month = $week->extendedBy(23);

echo $week->days();    // 7  — исходный объект не изменился
echo $month->days();   // 30

<?php
// app/Domain/TicketMetrics.php
declare(strict_types=1);

namespace App\Domain;

use DateTimeImmutable;

final class TicketMetrics
{
    /** Вычисляется при каждом чтении — хранить нечего. */
    public int $ageHours {
        get => (int) $this->createdAt->diff(new DateTimeImmutable())->days * 24;
    }

    /** Проверка при записи — некорректное значение не попадёт в объект. */
    public int $spentMinutes = 0 {
        set {
            if ($value < 0) {
                throw new \InvalidArgumentException('Затраченное время не бывает отрицательным');
            }

            $this->spentMinutes = $value;
        }
    }

    /** Нормализация при записи. */
    public string $subject {
        set => trim(preg_replace('/\s+/u', ' ', $value) ?? '');
    }

    public function __construct(
        public readonly DateTimeImmutable $createdAt,
        string $subject,
    ) {
        $this->subject = $subject;
    }
}

$metrics = new TicketMetrics(new DateTimeImmutable('-3 days'), '  Не   работает  VPN  ');

echo $metrics->subject;        // "Не работает VPN" — нормализовано при записи
echo $metrics->ageHours;       // 72 — посчитано при чтении
$metrics->spentMinutes = 45;   // проверено
// $metrics->spentMinutes = -1;  // InvalidArgumentException

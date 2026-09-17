<?php
// app/Domain/TicketSummary.php
declare(strict_types=1);

namespace App\Domain;

final class TicketSummary
{
    public int $total = 0;
    public int $open = 0;
    public float $averageHours = 0.0;
    public ?string $lastSubject = null;
    public array $byPriority = [];
}

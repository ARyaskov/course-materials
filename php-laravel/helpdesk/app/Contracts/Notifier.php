<?php
// app/Contracts/Notifier.php
declare(strict_types=1);

namespace App\Contracts;

use App\Models\User;

interface Notifier
{
    public function send(User $recipient, string $subject, string $body): void;

    public function supports(User $recipient): bool;

    public function channel(): string;
}

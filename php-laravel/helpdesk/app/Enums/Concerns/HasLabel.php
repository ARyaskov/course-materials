<?php
// app/Enums/Concerns/HasLabel.php
declare(strict_types=1);

namespace App\Enums\Concerns;

interface HasLabel
{
    public function label(): string;

    /** @return array<string, string> */
    public static function options(): array;
}

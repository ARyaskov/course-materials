<?php
// app/Contracts/ExportFormat.php
declare(strict_types=1);

namespace App\Contracts;

use Illuminate\Support\Collection;

interface ExportFormat
{
    public function extension(): string;

    public function mimeType(): string;

    /** @param  Collection<int, \App\Models\Ticket>  $tickets */
    public function render(Collection $tickets): string;
}

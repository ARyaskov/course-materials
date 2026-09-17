<?php
// app/Models/TicketTag.php
declare(strict_types=1);

namespace App\Models;

use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Relations\Pivot;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

final class TicketTag extends Pivot
{
    protected $table = 'ticket_tag';

    public $incrementing = false;

    protected function casts(): array
    {
        return ['created_at' => 'immutable_datetime'];
    }

    public function attachedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'attached_by');
    }

    public function isRecent(): bool
    {
        return $this->created_at?->isAfter(now()->subDay()) ?? false;
    }
}

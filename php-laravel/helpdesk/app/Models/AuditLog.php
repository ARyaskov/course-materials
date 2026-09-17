<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property int $id
 * @property string $action
 * @property int|null $user_id
 * @property string|null $ip
 * @property array<string, mixed>|null $payload
 * @property string|null $request_id
 */
final class AuditLog extends Model
{
    public const UPDATED_AT = null;

    protected $fillable = ['action', 'user_id', 'ip', 'payload', 'request_id'];

    protected function casts(): array
    {
        return ['payload' => 'array'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}

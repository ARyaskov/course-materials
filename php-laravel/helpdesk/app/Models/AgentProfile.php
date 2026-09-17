<?php

declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * @property int $id
 * @property int $user_id
 * @property string $department
 * @property int $max_tickets
 * @property-read User $user
 */
final class AgentProfile extends Model
{
    use HasFactory;

    protected $fillable = ['department', 'max_tickets'];

    protected function casts(): array
    {
        return ['max_tickets' => 'integer'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}

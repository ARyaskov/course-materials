<?php
// app/Models/Tag.php
declare(strict_types=1);

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\SoftDeletes;

final class Tag extends Model
{
    use HasFactory;
    use SoftDeletes;

    protected $fillable = ['slug', 'name', 'color'];

    public function tickets(): BelongsToMany
    {
        return $this->belongsToMany(Ticket::class, 'ticket_tag')
            ->withPivot(['attached_by', 'created_at']);
    }
}

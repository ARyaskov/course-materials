<?php
// app/Models/Booking.php
declare(strict_types=1);

namespace App\Models;

use App\Enums\BookingStatus;
use Illuminate\Database\Eloquent\Attributes\Scope;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Str;

final class Booking extends Model
{
    use HasFactory;

    protected $fillable = ['seats'];

    protected function casts(): array
    {
        return [
            'status' => BookingStatus::class,
            'seats' => 'integer',
            'held_until' => 'immutable_datetime',
            'confirmed_at' => 'immutable_datetime',
            'cancelled_at' => 'immutable_datetime',
        ];
    }

    public function getRouteKeyName(): string
    {
        return 'reference';
    }

    protected static function booted(): void
    {
        static::creating(function (self $booking): void {
            $booking->reference ??= 'BK-' . Str::upper(Str::random(10));
        });
    }

    public function event(): BelongsTo
    {
        return $this->belongsTo(Event::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    #[Scope]
    protected function active(Builder $query): void
    {
        $query->whereIn('status', [BookingStatus::Held, BookingStatus::Confirmed]);
    }

    #[Scope]
    protected function expiring(Builder $query): void
    {
        $query->where('status', BookingStatus::Held)
            ->where('held_until', '<=', now());
    }

    public function isOwnedBy(User $user): bool
    {
        return $this->user_id === $user->id;
    }
}

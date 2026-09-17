<?php
// app/Models/Event.php
declare(strict_types=1);

namespace App\Models;

use App\Enums\BookingStatus;
use App\Enums\EventStatus;
use Illuminate\Database\Eloquent\Attributes\Scope;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Str;

#[UseFactory(\Database\Factories\EventFactory::class)]
final class Event extends Model
{
    use HasFactory;
    use SoftDeletes;

    protected $fillable = [
        'title', 'description', 'venue', 'capacity', 'price', 'starts_at', 'ends_at',
    ];

    protected function casts(): array
    {
        return [
            'status' => EventStatus::class,
            'capacity' => 'integer',
            'price' => 'integer',
            'starts_at' => 'immutable_datetime',
            'ends_at' => 'immutable_datetime',
            'published_at' => 'immutable_datetime',
        ];
    }

    public function getRouteKeyName(): string
    {
        return 'slug';
    }

    protected static function booted(): void
    {
        static::creating(function (self $event): void {
            $event->slug ??= Str::slug($event->title) . '-' . Str::lower(Str::random(6));
        });
    }

    public function organizer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'organizer_id');
    }

    public function bookings(): HasMany
    {
        return $this->hasMany(Booking::class);
    }

    public function participants(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'bookings')
            ->withPivot(['seats', 'status', 'reference'])
            ->wherePivotIn('status', [BookingStatus::Held->value, BookingStatus::Confirmed->value])
            ->withTimestamps();
    }

    #[Scope]
    protected function published(Builder $query): void
    {
        $query->where('status', EventStatus::Published);
    }

    #[Scope]
    protected function upcoming(Builder $query): void
    {
        $query->where('starts_at', '>', now());
    }

    #[Scope]
    protected function bookable(Builder $query): void
    {
        $query->published()->upcoming();
    }

    public function occupiedSeats(): int
    {
        return (int) $this->bookings()
            ->whereIn('status', [BookingStatus::Held, BookingStatus::Confirmed])
            ->sum('seats');
    }

    public function availableSeats(): int
    {
        return max(0, $this->capacity - $this->occupiedSeats);
    }

    public function isBookable(): bool
    {
        return $this->status->isBookable() && $this->starts_at->isFuture();
    }
}

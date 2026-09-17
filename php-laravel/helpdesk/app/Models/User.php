<?php
// app/Models/User.php
declare(strict_types=1);

namespace App\Models;

use App\Enums\UserRole;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasManyThrough;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

final class User extends Authenticatable
{
    use HasApiTokens;
    use HasFactory;
    use Notifiable;

    protected $fillable = ['name', 'email', 'password', 'role', 'settings', 'push_token', 'webhook_url'];

    protected $hidden = ['password', 'remember_token'];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'role' => UserRole::class,
            'settings' => 'array',
            'email_verified_at' => 'immutable_datetime',
        ];
    }

    public function tickets(): HasMany
    {
        return $this->hasMany(Ticket::class, 'author_id');
    }

    public function assignedTickets(): HasMany
    {
        return $this->hasMany(Ticket::class, 'assignee_id');
    }

    public function agentProfile(): HasOne
    {
        return $this->hasOne(AgentProfile::class);
    }

    public function subscriptions(): BelongsToMany
    {
        return $this->belongsToMany(Ticket::class, 'ticket_subscriptions')
            ->withPivot(['is_muted', 'reason'])
            ->withTimestamps();
    }

    public function ticketComments(): HasManyThrough
    {
        return $this->hasManyThrough(Comment::class, Ticket::class, 'author_id', 'ticket_id');
    }

    public function isAgent(): bool
    {
        return in_array($this->role, [UserRole::Agent, UserRole::Admin], strict: true);
    }

    public function isAdmin(): bool
    {
        return $this->role === UserRole::Admin;
    }
}

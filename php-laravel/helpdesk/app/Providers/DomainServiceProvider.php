<?php
// app/Providers/DomainServiceProvider.php
declare(strict_types=1);

namespace App\Providers;

use App\Models\Comment;
use App\Observers\CommentObserver;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

final class DomainServiceProvider extends ServiceProvider
{
    public function boot(): void
    {
        // строгий режим включается в AppServiceProvider; здесь — только домен
        Comment::observe(CommentObserver::class);

        Gate::before(fn ($user) => $user->isAdmin() ? true : null);
        Gate::define('view-stats', fn ($user): bool => $user->isAgent());
    }
}

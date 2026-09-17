<?php
// app/Models/Scopes/VisibleToUserScope.php
declare(strict_types=1);

namespace App\Models\Scopes;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Scope;

final readonly class VisibleToUserScope implements Scope
{
    public function apply(Builder $builder, Model $model): void
    {
        $user = auth()->user();

        if ($user === null || $user->isAgent()) {
            return;
        }

        $builder->where('author_id', $user->id);
    }
}

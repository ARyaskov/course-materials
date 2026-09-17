<?php
// app/Services/TagResolver.php
declare(strict_types=1);

namespace App\Services;

use App\Models\Tag;

final readonly class TagResolver
{
    /**
     * @param  list<string>  $slugs
     * @return list<int>
     */
    public function idsBySlugs(array $slugs): array
    {
        if ($slugs === []) {
            return [];
        }

        return Tag::query()->whereIn('slug', $slugs)->pluck('id')->all();
    }
}

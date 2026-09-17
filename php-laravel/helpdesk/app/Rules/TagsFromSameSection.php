<?php
// app/Rules/TagsFromSameSection.php
declare(strict_types=1);

namespace App\Rules;

use App\Models\Tag;
use Closure;
use Illuminate\Contracts\Validation\DataAwareRule;
use Illuminate\Contracts\Validation\ValidationRule;

final class TagsFromSameSection implements DataAwareRule, ValidationRule
{
    /** @var array<string, mixed> */
    private array $data = [];

    public function setData(array $data): static
    {
        $this->data = $data;

        return $this;
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_array($value) || count($value) < 2) {
            return;
        }

        $sections = Tag::query()->whereIn('slug', $value)->distinct()->pluck('section');

        if ($sections->count() > 1) {
            $fail('Метки должны относиться к одному разделу: ' . $sections->implode(', ') . '.');
        }
    }
}

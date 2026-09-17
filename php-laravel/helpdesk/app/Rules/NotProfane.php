<?php
// app/Rules/NotProfane.php
declare(strict_types=1);

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

final readonly class NotProfane implements ValidationRule
{
    /** @param  list<string>  $blacklist */
    public function __construct(private array $blacklist = [])
    {
    }

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if (! is_string($value)) {
            return;   // тип проверяет отдельное правило
        }

        $words = $this->blacklist !== [] ? $this->blacklist : config('helpdesk.profanity', []);
        $normalized = mb_strtolower($value);

        foreach ($words as $word) {
            if (str_contains($normalized, mb_strtolower($word))) {
                $fail('Поле :attribute содержит недопустимые слова.');

                return;
            }
        }
    }
}

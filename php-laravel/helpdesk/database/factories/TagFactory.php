<?php

declare(strict_types=1);

namespace Database\Factories;

use App\Models\Tag;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/** @extends Factory<Tag> */
final class TagFactory extends Factory
{
    protected $model = Tag::class;

    public function definition(): array
    {
        $name = $this->faker->unique()->word();

        return [
            'slug' => Str::slug($name) . '-' . Str::lower(Str::random(4)),
            'name' => Str::ucfirst($name),
            'color' => $this->faker->randomElement(['gray', 'red', 'green', 'blue', 'amber']),
        ];
    }
}

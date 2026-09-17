<?php
// database/seeders/TagSeeder.php
declare(strict_types=1);

namespace Database\Seeders;

use App\Models\Tag;
use Illuminate\Database\Seeder;

final class TagSeeder extends Seeder
{
    private const array TAGS = [
        ['slug' => 'vpn',      'name' => 'VPN'],
        ['slug' => 'network',  'name' => 'Сеть'],
        ['slug' => 'hardware', 'name' => 'Оборудование'],
        ['slug' => 'access',   'name' => 'Доступы'],
        ['slug' => 'software', 'name' => 'Программы'],
    ];

    public function run(): void
    {
        foreach (self::TAGS as $tag) {
            Tag::query()->updateOrCreate(['slug' => $tag['slug']], $tag);
        }
    }
}

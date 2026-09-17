<?php

declare(strict_types=1);

namespace App\Tests\Unit;

use PHPUnit\Framework\Attributes\{DataProvider, Test};
use PHPUnit\Framework\TestCase;

final class ArchitectureTest extends TestCase
{
    /** @return iterable<string, array{string, list<string>}> */
    public static function layerRules(): iterable
    {
        yield 'Domain ни от чего не зависит' => [
            'src/Domain',
            ['Yiisoft\\', 'Psr\\Http\\', 'GuzzleHttp\\', 'Symfony\\',
             'App\\Infrastructure', 'App\\Api', 'App\\Application'],
        ];

        yield 'Application не знает про HTTP и БД' => [
            'src/Application',
            ['Psr\\Http\\Message', 'Psr\\Http\\Server', 'App\\Api',
             'App\\Infrastructure', 'Yiisoft\\Db'],
        ];

        yield 'Infrastructure не зависит от Api' => [
            'src/Infrastructure',
            ['App\\Api\\Action', 'App\\Api\\Middleware'],
        ];
    }

    /** @param list<string> $forbidden */
    #[Test]
    #[DataProvider('layerRules')]
    public function направление_зависимостей_не_нарушено(
        string $directory,
        array $forbidden,
    ): void {
        $root = dirname(__DIR__, 2);
        $violations = [];

        $files = new \RegexIterator(
            new \RecursiveIteratorIterator(
                new \RecursiveDirectoryIterator($root . '/' . $directory),
            ),
            '/\.php$/',
        );

        foreach ($files as $file) {
            preg_match_all('/^use\s+([^;]+);/m', file_get_contents($file->getPathname()), $m);

            foreach ($m[1] as $import) {
                foreach ($forbidden as $prefix) {
                    if (str_starts_with($import, $prefix)) {
                        $violations[] = sprintf('%s → %s',
                            str_replace($root . '/', '', $file->getPathname()), $import);
                    }
                }
            }
        }

        self::assertSame([], $violations,
            "Нарушения:\n  " . implode("\n  ", $violations));
    }
}

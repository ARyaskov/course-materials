<?php
// tests/Architecture/ConfigTest.php
declare(strict_types=1);

it('env() вызывается только в config', function (): void {
    $violations = collect(\Symfony\Component\Finder\Finder::create()->files()->in(app_path())->name('*.php'))
        ->filter(fn ($file): bool => (bool) preg_match('/\benv\s*\(/', $file->getContents()))
        ->map(fn ($file): string => str_replace(base_path(), '', $file->getPathname()))
        ->values();

    expect($violations)->toBeEmpty();
});

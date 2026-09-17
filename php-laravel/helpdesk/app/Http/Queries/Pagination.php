<?php
// app/Http/Queries/Pagination.php
declare(strict_types=1);

namespace App\Http\Queries;

use Illuminate\Http\Request;

final readonly class Pagination
{
    public const int DEFAULT = 20;
    public const int MAX = 100;

    private function __construct(public int $perPage, public bool $cursor)
    {
    }

    public static function fromRequest(Request $request): self
    {
        return new self(
            perPage: min(max($request->integer('per_page', self::DEFAULT), 1), self::MAX),
            cursor: $request->boolean('cursor'),
        );
    }
}

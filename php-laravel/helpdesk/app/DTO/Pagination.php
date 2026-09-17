<?php
// app/DTO/Pagination.php
declare(strict_types=1);

namespace App\DTO;

use Illuminate\Http\Request;

final readonly class Pagination
{
    public const int MAX_PER_PAGE = 100;

    private function __construct(
        public int $page,
        public int $perPage,
    ) {
    }

    public static function of(int $page = 1, int $perPage = 20): self
    {
        return new self(
            page: max($page, 1),
            perPage: min(max($perPage, 1), self::MAX_PER_PAGE),
        );
    }

    public static function fromRequest(Request $request): self
    {
        return self::of(
            page: $request->integer('page', 1),
            perPage: $request->integer('per_page', 20),
        );
    }

    public function offset(): int
    {
        return ($this->page - 1) * $this->perPage;
    }
}

$p = Pagination::of(perPage: 5000);

echo $p->perPage;   // 100 — ограничено
echo $p->offset();  // 0

<?php
// app/Http/Middleware/DetectPostSizeExceeded.php
declare(strict_types=1);

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

final class DetectPostSizeExceeded
{
    public function handle(Request $request, Closure $next): Response
    {
        $contentLength = (int) $request->server('CONTENT_LENGTH', 0);
        $limit = $this->toBytes(ini_get('post_max_size'));

        if ($limit > 0 && $contentLength > $limit && $request->isMethod('post')) {
            return response()->json([
                'message' => 'Размер запроса превышает допустимый.',
                'code'    => 'payload_too_large',
                'max_mb'  => round($limit / 1024 / 1024, 1),
            ], 413);
        }

        return $next($request);
    }

    private function toBytes(string|false $value): int
    {
        if ($value === false || $value === '') {
            return 0;
        }

        $unit = strtolower(substr($value, -1));
        $number = (int) $value;

        return match ($unit) {
            'g' => $number * 1024 ** 3,
            'm' => $number * 1024 ** 2,
            'k' => $number * 1024,
            default => $number,
        };
    }
}

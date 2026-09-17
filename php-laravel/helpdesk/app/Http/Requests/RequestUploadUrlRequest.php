<?php

declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

final class RequestUploadUrlRequest extends FormRequest
{
    private const array ALLOWED_MIMES = [
        'image/png',
        'image/jpeg',
        'application/pdf',
        'text/plain',
    ];

    public function rules(): array
    {
        return [
            'filename' => ['required', 'string', 'max:200', 'regex:/^[\w\-. ]+$/u'],
            'mime' => ['required', 'string', Rule::in(self::ALLOWED_MIMES)],
            'size' => ['required', 'integer', 'min:1', 'max:' . (config('helpdesk.attachments.max_size_mb', 16) * 1024 * 1024)],
        ];
    }

    public function messages(): array
    {
        return [
            'filename.regex' => 'В имени файла допустимы буквы, цифры, пробел, точка, дефис и подчёркивание.',
            'size.max' => 'Файл больше допустимого размера.',
        ];
    }
}

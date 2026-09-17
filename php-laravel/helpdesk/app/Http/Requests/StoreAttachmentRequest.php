<?php
// app/Http/Requests/StoreAttachmentRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Validation\Rules\File;

final class StoreAttachmentRequest extends ApiRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('comment', $this->route('ticket'));
    }

    public function rules(): array
    {
        return [
            'attachment' => [
                'required',
                File::types(['png', 'jpg', 'jpeg', 'pdf', 'txt', 'csv'])
                    ->max(config('helpdesk.attachments.max_size_mb') * 1024),
            ],
            'description' => ['nullable', 'string', 'max:200'],
        ];
    }

    public function messages(): array
    {
        return [
            'attachment.required' => 'Выберите файл для загрузки.',
            'attachment.max'      => 'Файл больше :max КБ.',
            'attachment.mimes'    => 'Допустимые форматы: PNG, JPEG, PDF, TXT, CSV.',
        ];
    }

    public function after(): array
    {
        return [
            function (\Illuminate\Validation\Validator $validator): void {
                $ticket = $this->route('ticket');
                $limit = config('helpdesk.limits.attachments_per_ticket');

                if ($ticket->attachments()->count() >= $limit) {
                    $validator->errors()->add('attachment', "К заявке нельзя приложить больше {$limit} файлов.");
                }
            },
        ];
    }
}

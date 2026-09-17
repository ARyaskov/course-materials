<?php
// app/Http/Requests/ApiRequest.php
declare(strict_types=1);

namespace App\Http\Requests;

use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Http\Exceptions\HttpResponseException;

abstract class ApiRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;   // наследники переопределяют
    }

    /** Единый формат ответа при провале валидации. */
    protected function failedValidation(Validator $validator): never
    {
        throw new HttpResponseException(
            response()->json([
                'message' => 'Данные не прошли проверку.',
                'code'    => 'validation_failed',
                'errors'  => $validator->errors()->toArray(),
            ], 422)
        );
    }

    /** Единый формат при отказе в правах. */
    protected function failedAuthorization(): never
    {
        throw new HttpResponseException(
            response()->json([
                'message' => 'Недостаточно прав для этой операции.',
                'code'    => 'forbidden',
            ], 403)
        );
    }

    protected function prepareForValidation(): void
    {
        // общая нормализация строковых полей
        $trimmed = [];

        foreach (['subject', 'name', 'email', 'body'] as $field) {
            if ($this->has($field) && is_string($this->input($field))) {
                $trimmed[$field] = trim($this->input($field));
            }
        }

        if ($trimmed !== []) {
            $this->merge($trimmed);
        }
    }
}

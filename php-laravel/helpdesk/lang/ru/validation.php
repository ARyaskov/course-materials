<?php
// lang/ru/validation.php — общие формулировки для всего приложения
declare(strict_types=1);

return [
    'required' => 'Поле :attribute обязательно для заполнения.',
    'min'      => [
        'string'  => 'Поле :attribute не короче :min символов.',
        'numeric' => 'Поле :attribute не меньше :min.',
        'array'   => 'Поле :attribute должно содержать не менее :min элементов.',
    ],
    'max' => [
        'string' => 'Поле :attribute не длиннее :max символов.',
        'file'   => 'Файл :attribute не больше :max килобайт.',
    ],
    'email'  => 'Поле :attribute должно быть корректным адресом электронной почты.',
    'exists' => 'Выбранное значение :attribute некорректно.',
    'unique' => 'Такое значение :attribute уже используется.',

    'attributes' => [
        'email'    => 'адрес электронной почты',
        'password' => 'пароль',
        'name'     => 'имя',
    ],
];

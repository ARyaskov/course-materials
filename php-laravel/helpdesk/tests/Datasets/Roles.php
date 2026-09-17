<?php
// tests/Datasets/Roles.php
declare(strict_types=1);

dataset('матрица доступа', [
    //                    роль        view  update close assign delete
    'автор'           => ['author',   true, true,  true, false, false],
    'исполнитель'     => ['assignee', true, true,  true, false, true],
    'сотрудник'       => ['agent',    true, true,  true, true,  true],
    'администратор'   => ['admin',    true, true,  true, true,  true],
    'посторонний'     => ['stranger', false,false, false,false, false],
]);

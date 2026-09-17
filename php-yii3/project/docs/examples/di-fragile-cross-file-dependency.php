<?php
// ХРУПКО: результат зависит от того, какой файл прочитан раньше
return ['app.timeout' => 5];

// config/common/di/b.php
return ['some.service' => ['__construct()' => ['timeout' => $definitions['app.timeout']]]];

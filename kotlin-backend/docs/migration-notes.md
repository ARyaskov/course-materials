# Заметки о внедрении Kotlin в PayGate (урок 16.2)

- Точка входа: тесты (Kotest, MockK) → модуль `paygate-api` с DTO → extension-утилиты → новые модули.
- Не мигрируем: `jpa-entities` (Lombok + JPA — kotlin-jpa/allopen, lateinit, мало выигрыша), `core-legacy` (стабилен), генерируемый код.
- Автоконвертер: только тесты и DTO; классы с логикой — руками по методу.
- Инциденты первого месяца: `Inconsistent JVM-target`, отсутствие `jackson-module-kotlin`, `@Transactional` на final-классе без `kotlin-spring`.
- Метрика: `cloc --include-lang=Java,Kotlin` раз в спринт; 61 % Kotlin через 8 месяцев.

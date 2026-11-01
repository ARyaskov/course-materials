-- diagnostic: safe to re-run
/*
  000_batch_demo.sql — пакеты, GO, область видимости переменных, @@ROWCOUNT, IF без BEGIN…END (урок 1.5).
  Не зависит от объектов demo.* (выполняется раньше 010_playground.sql).
*/
USE Waybill;
GO
SET NOCOUNT ON;
GO

-- Пакет 1: переменная объявлена и напечатана
DECLARE @today date = CURRENT_DATE;
PRINT CONCAT('Пакет 1, @today = ', @today);
GO

-- Пакет 2: та же переменная недоступна — строка закомментирована, иначе ошибка 137
-- SELECT @today;
PRINT 'Пакет 2: переменная из пакета 1 не видна';
GO

-- Пакет 3: WHILE вместо GENERATE_SERIES и поведение @@ROWCOUNT
DECLARE @t TABLE (n int NOT NULL PRIMARY KEY);
DECLARE @i int = 1;
WHILE @i <= 20
BEGIN
    INSERT INTO @t (n) VALUES (@i);
    SET @i += 1;
END;
SELECT COUNT(*) AS inserted_rows FROM @t;
PRINT CONCAT('@@ROWCOUNT после SELECT COUNT(*) = ', @@ROWCOUNT);   -- 1: строка результата SELECT
INSERT INTO @t (n) SELECT value FROM GENERATE_SERIES(21, 30);
PRINT CONCAT('@@ROWCOUNT после INSERT ... SELECT = ', @@ROWCOUNT);  -- 10
GO

-- Пакет 4: IF управляет ровно одной инструкцией без BEGIN…END
DECLARE @pending int = 0;
IF @pending > 0
    PRINT 'условие истинно';
    PRINT 'эта строка печатается всегда — она вне IF';
IF @pending > 0
BEGIN
    PRINT 'условие истинно';
    PRINT 'обе строки внутри условия';
END;
GO

/*
  020_backup_restore.sql — резервное копирование Waybill (глава 16).

  ops.usp_BackupDatabase @Type = 'FULL'|'DIFF'|'LOG', @Path = NULL (InstanceDefaultBackupPath), @CopyOnly = 0
    - имя файла Waybill_<type>_<yyyyMMdd_HHmmss>.bak/.trn; CHECKSUM; COMPRESSION (ALGORITHM = ZSTD, LEVEL = …) — SQL Server 2025,
      при ошибке синтаксиса (старая сборка) — обычное сжатие; ENCRYPTION сертификатом WaybillTdeCert, если он есть;
      TO URL (S3) — при ops.Setting 'backup.url' (например s3://minio:9000/waybill-backups/) и credential с тем же именем.
    - результат в ops.BackupRun (+ msdb.dbo.backupset как источник истины).
  ops.usp_VerifyLastBackup — RESTORE VERIFYONLY последнего полного бэкапа.
  ops.vw_BackupHistory     — msdb.dbo.backupset за 30 дней: тип, размер, сжатие, длительность, шифрование.
  ops.usp_RestoreScript @PointInTime — печатает последовательность RESTORE (FULL → DIFF → LOG … STOPAT) для восстановления
    в базу Waybill_Restore на этом же сервере (WITH MOVE); не выполняет.
  Идемпотентен; первый прогон делает FULL + LOG (цепочка журналов начинается здесь).
*/
USE Waybill;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

INSERT INTO ops.Setting (Name, Value) SELECT 'backup.url', N'' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'backup.url');
INSERT INTO ops.Setting (Name, Value) SELECT 'backup.zstd_level', N'MEDIUM' WHERE NOT EXISTS (SELECT 1 FROM ops.Setting WHERE Name = 'backup.zstd_level');
GO

IF OBJECT_ID(N'ops.BackupRun', N'U') IS NULL
CREATE TABLE ops.BackupRun
(
    BackupRunId  int IDENTITY CONSTRAINT PK_BackupRun PRIMARY KEY,
    StartedAt    datetime2(3) NOT NULL,
    FinishedAt   datetime2(3) NULL,
    BackupType   char(4)      NOT NULL,     -- FULL / DIFF / LOG
    Target       nvarchar(400) NOT NULL,
    Algorithm    varchar(16)  NULL,         -- ZSTD / MSXPRESS / NONE
    Encrypted    bit          NOT NULL CONSTRAINT DF_BackupRun_Encrypted DEFAULT (0),
    SizeMb       decimal(12, 1) NULL,
    Success      bit          NOT NULL CONSTRAINT DF_BackupRun_Success DEFAULT (0),
    Error        nvarchar(1000) NULL
);
GO

CREATE OR ALTER PROCEDURE ops.usp_BackupDatabase
    @Type char(4) = 'FULL', @Path nvarchar(260) = NULL, @CopyOnly bit = 0
AS
BEGIN
    SET NOCOUNT ON;
    IF @Type NOT IN ('FULL', 'DIFF', 'LOG') THROW 50100, 'Тип бэкапа: FULL, DIFF или LOG', 1;

    DECLARE @url nvarchar(400) = (SELECT Value FROM ops.Setting WHERE Name = 'backup.url');
    DECLARE @level nvarchar(10) = ISNULL((SELECT Value FROM ops.Setting WHERE Name = 'backup.zstd_level'), N'MEDIUM');
    DECLARE @stamp nvarchar(20) = FORMAT(SYSUTCDATETIME(), 'yyyyMMdd_HHmmss');
    DECLARE @ext nvarchar(4) = IIF(@Type = 'LOG', N'.trn', N'.bak');
    DECLARE @file nvarchar(200) = CONCAT(N'Waybill_', LOWER(@Type), N'_', @stamp, @ext);
    DECLARE @target nvarchar(400), @toClause nvarchar(500);
    IF @url <> N''
    BEGIN
        SET @target = @url + @file;
        SET @toClause = N'TO URL = ' + QUOTENAME(@target, '''');
    END
    ELSE
    BEGIN
        SET @Path = ISNULL(@Path, CAST(SERVERPROPERTY('InstanceDefaultBackupPath') AS nvarchar(260)));
        IF RIGHT(@Path, 1) NOT IN (N'\', N'/') SET @Path += IIF(CHARINDEX(N'/', @Path) > 0, N'/', N'\');
        SET @target = @Path + @file;
        SET @toClause = N'TO DISK = ' + QUOTENAME(@target, '''');
    END

    DECLARE @encrypt bit = IIF(EXISTS (SELECT 1 FROM master.sys.certificates WHERE name = N'WaybillTdeCert'), 1, 0);
    DECLARE @encClause nvarchar(200) = IIF(@encrypt = 1, N', ENCRYPTION (ALGORITHM = AES_256, SERVER CERTIFICATE = WaybillTdeCert)', N'');
    DECLARE @what nvarchar(100) = CASE @Type WHEN 'LOG' THEN N'BACKUP LOG Waybill' ELSE N'BACKUP DATABASE Waybill' END;
    DECLARE @opts nvarchar(300) = CONCAT(N'CHECKSUM, STATS = 25, MAXTRANSFERSIZE = 4194304',
                                         IIF(@Type = 'DIFF', N', DIFFERENTIAL', N''), IIF(@CopyOnly = 1, N', COPY_ONLY', N''));

    INSERT INTO ops.BackupRun (StartedAt, BackupType, Target, Encrypted) VALUES (SYSUTCDATETIME(), @Type, @target, @encrypt);
    DECLARE @runId int = SCOPE_IDENTITY(), @sql nvarchar(max), @algorithm varchar(16);

    BEGIN TRY
        -- SQL Server 2025: ZSTD с уровнем; на сборках без ZSTD — синтаксическая ошибка → обычное сжатие
        SET @algorithm = 'ZSTD';
        SET @sql = CONCAT(@what, N' ', @toClause, N' WITH ', @opts, N', COMPRESSION (ALGORITHM = ZSTD, LEVEL = ', @level, N')', @encClause, N';');
        BEGIN TRY
            EXEC sys.sp_executesql @sql;
        END TRY
        BEGIN CATCH
            IF ERROR_NUMBER() NOT IN (102, 155, 156, 319) THROW;   -- не синтаксис — настоящая ошибка бэкапа
            SET @algorithm = 'MSXPRESS';
            SET @sql = CONCAT(@what, N' ', @toClause, N' WITH ', @opts, N', COMPRESSION', @encClause, N';');
            EXEC sys.sp_executesql @sql;
        END CATCH

        UPDATE r SET FinishedAt = SYSUTCDATETIME(), Success = 1, Algorithm = @algorithm,
               SizeMb = (SELECT TOP (1) CAST(bs.compressed_backup_size / 1048576.0 AS decimal(12, 1))
                         FROM msdb.dbo.backupset AS bs JOIN msdb.dbo.backupmediafamily AS mf ON mf.media_set_id = bs.media_set_id
                         WHERE bs.database_name = N'Waybill' AND mf.physical_device_name = @target ORDER BY bs.backup_finish_date DESC)
        FROM ops.BackupRun AS r WHERE r.BackupRunId = @runId;
        PRINT CONCAT(@Type, ' backup → ', @target, ' (', @algorithm, IIF(@encrypt = 1, ', encrypted', ''), ')');
    END TRY
    BEGIN CATCH
        UPDATE ops.BackupRun SET FinishedAt = SYSUTCDATETIME(), Success = 0, Error = ERROR_MESSAGE() WHERE BackupRunId = @runId;
        THROW;
    END CATCH
END;
GO

-- msdb.dbo.backupset.compression_algorithm появился в SQL Server 2025; на старых сборках столбца нет
DECLARE @alg nvarchar(100) = IIF(COL_LENGTH(N'msdb.dbo.backupset', N'compression_algorithm') IS NOT NULL,
                                 N'bs.compression_algorithm AS Algorithm', N'CAST(NULL AS nvarchar(32)) AS Algorithm');
DECLARE @view nvarchar(max) = N'CREATE OR ALTER VIEW ops.vw_BackupHistory
AS
' + REPLACE(N'SELECT bs.backup_start_date AS StartedAt, bs.backup_finish_date AS FinishedAt,
       DATEDIFF(second, bs.backup_start_date, bs.backup_finish_date) AS Seconds,
       CASE bs.type WHEN ''D'' THEN ''FULL'' WHEN ''I'' THEN ''DIFF'' WHEN ''L'' THEN ''LOG'' ELSE bs.type END AS BackupType,
       bs.is_copy_only AS CopyOnly,
       CAST(bs.backup_size / 1048576.0 AS decimal(12, 1)) AS SizeMb,
       CAST(bs.compressed_backup_size / 1048576.0 AS decimal(12, 1)) AS CompressedMb,
       CAST(bs.backup_size / NULLIF(bs.compressed_backup_size, 0) AS decimal(6, 2)) AS Ratio,
       __ALG__,
       bs.key_algorithm AS EncryptionAlgorithm, bs.encryptor_type AS EncryptorType,
       bs.has_backup_checksums AS Checksum,
       bs.first_lsn, bs.last_lsn, bs.checkpoint_lsn, bs.database_backup_lsn,
       mf.physical_device_name AS Target, bs.user_name AS RunBy, bs.server_name AS ServerName
FROM msdb.dbo.backupset AS bs
JOIN msdb.dbo.backupmediafamily AS mf ON mf.media_set_id = bs.media_set_id
WHERE bs.database_name = N''Waybill'' AND bs.backup_start_date >= DATEADD(day, -30, GETDATE())
  AND bs.database_guid = (SELECT database_guid FROM sys.database_recovery_status WHERE database_id = DB_ID());', N'__ALG__', @alg);   -- guid: только текущая база, не предшественница с тем же именем
EXEC sys.sp_executesql @view;
GO

CREATE OR ALTER PROCEDURE ops.usp_VerifyLastBackup
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @target nvarchar(400) = (SELECT TOP (1) Target FROM ops.vw_BackupHistory WHERE BackupType = 'FULL' ORDER BY StartedAt DESC);
    IF @target IS NULL BEGIN PRINT 'нет полного бэкапа'; RETURN; END
    DECLARE @sql nvarchar(max) = CONCAT(N'RESTORE VERIFYONLY FROM ', IIF(@target LIKE N's3://%' OR @target LIKE N'https://%', N'URL', N'DISK'), N' = ', QUOTENAME(@target, ''''), N' WITH CHECKSUM;');
    EXEC sys.sp_executesql @sql;
    PRINT CONCAT('verified: ', @target);
END;
GO

-- Скрипт восстановления на момент времени: печатает, не выполняет ----------------------------------
CREATE OR ALTER PROCEDURE ops.usp_RestoreScript
    @PointInTime datetime2(0) = NULL, @TargetDatabase sysname = N'Waybill_Restore'
AS
BEGIN
    SET NOCOUNT ON;
    SET @PointInTime = ISNULL(@PointInTime, SYSDATETIME());
    DECLARE @dataPath nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS nvarchar(260));
    DECLARE @logPath  nvarchar(260) = CAST(SERVERPROPERTY('InstanceDefaultLogPath')  AS nvarchar(260));

    -- Последний FULL до момента → последний DIFF после него → все LOG после (или после FULL) до первого, покрывающего момент
    DECLARE @full TABLE (Target nvarchar(400), FinishedAt datetime, checkpoint_lsn numeric(25, 0));
    INSERT INTO @full SELECT TOP (1) Target, FinishedAt, checkpoint_lsn FROM ops.vw_BackupHistory
        WHERE BackupType = 'FULL' AND CopyOnly = 0 AND FinishedAt <= @PointInTime ORDER BY FinishedAt DESC;
    IF NOT EXISTS (SELECT 1 FROM @full) BEGIN PRINT '-- нет полного бэкапа до указанного момента'; RETURN; END

    DECLARE @diff TABLE (Target nvarchar(400), FinishedAt datetime, last_lsn numeric(25, 0));
    INSERT INTO @diff SELECT TOP (1) h.Target, h.FinishedAt, h.last_lsn FROM ops.vw_BackupHistory AS h CROSS JOIN @full AS f
        WHERE h.BackupType = 'DIFF' AND h.FinishedAt <= @PointInTime AND h.database_backup_lsn = f.checkpoint_lsn ORDER BY h.FinishedAt DESC;

    DECLARE @afterLsn numeric(25, 0) = ISNULL((SELECT last_lsn FROM @diff), (SELECT checkpoint_lsn FROM @full));

    DECLARE @lines TABLE (Seq int IDENTITY, Line nvarchar(max));
    -- MOVE для каждого файла базы (данные, FG_Events, FG_Memory при наличии, журнал) — из sys.database_files
    DECLARE @moves nvarchar(max) = (
        SELECT STRING_AGG(CONCAT(N' MOVE ', QUOTENAME(f.name, ''''), N' TO ',
                                 QUOTENAME(CASE WHEN f.type_desc = N'LOG' THEN @logPath ELSE @dataPath END + @TargetDatabase + N'_' + f.name
                                           + CASE f.type_desc WHEN N'LOG' THEN N'.ldf' WHEN N'ROWS' THEN IIF(f.file_id = 1, N'.mdf', N'.ndf') ELSE N'' END, '''')), N',')
               WITHIN GROUP (ORDER BY f.file_id)
        FROM sys.database_files AS f);
    INSERT INTO @lines (Line)
    SELECT CONCAT(N'RESTORE DATABASE ', QUOTENAME(@TargetDatabase), N' FROM DISK = ', QUOTENAME(Target, ''''), N' WITH NORECOVERY, CHECKSUM, STATS = 10,', @moves, N';')
    FROM @full;
    INSERT INTO @lines (Line)
    SELECT CONCAT(N'RESTORE DATABASE ', QUOTENAME(@TargetDatabase), N' FROM DISK = ', QUOTENAME(Target, ''''), N' WITH NORECOVERY, CHECKSUM;') FROM @diff;
    INSERT INTO @lines (Line)
    SELECT CONCAT(N'RESTORE LOG ', QUOTENAME(@TargetDatabase), N' FROM DISK = ', QUOTENAME(h.Target, ''''), N' WITH NORECOVERY, CHECKSUM',
                  IIF(h.FinishedAt > @PointInTime, CONCAT(N', STOPAT = ', QUOTENAME(CONVERT(nvarchar(30), @PointInTime, 120), '''')), N''), N';')
    FROM ops.vw_BackupHistory AS h
    WHERE h.BackupType = 'LOG' AND h.last_lsn > @afterLsn
      AND h.StartedAt <= (SELECT MIN(x.FinishedAt) FROM ops.vw_BackupHistory AS x WHERE x.BackupType = 'LOG' AND x.FinishedAt > @PointInTime)
    ORDER BY h.first_lsn;
    INSERT INTO @lines (Line) VALUES (CONCAT(N'RESTORE DATABASE ', QUOTENAME(@TargetDatabase), N' WITH RECOVERY;'));

    SELECT Seq, Line FROM @lines ORDER BY Seq;
END;
GO
GRANT EXECUTE ON ops.usp_BackupDatabase TO waybill_ops;
GRANT EXECUTE ON ops.usp_VerifyLastBackup TO waybill_ops;
GRANT EXECUTE ON ops.usp_RestoreScript TO waybill_ops;
GRANT SELECT ON ops.vw_BackupHistory TO waybill_ops;
GO

-- Первый прогон: начать цепочку (FULL + LOG), проверить, напечатать скрипт восстановления
-- database_guid: у пересозданной базы с тем же именем в msdb остаются чужие записи — цепочку начинают заново
IF NOT EXISTS (SELECT 1 FROM msdb.dbo.backupset WHERE database_name = N'Waybill' AND type = 'D' AND is_copy_only = 0
               AND database_guid = (SELECT database_guid FROM sys.database_recovery_status WHERE database_id = DB_ID()))
    EXEC ops.usp_BackupDatabase @Type = 'FULL';
EXEC ops.usp_BackupDatabase @Type = 'LOG';
EXEC ops.usp_VerifyLastBackup;
SELECT StartedAt, BackupType, SizeMb, CompressedMb, Ratio, Algorithm, EncryptionAlgorithm, Seconds, Target FROM ops.vw_BackupHistory ORDER BY StartedAt DESC;
EXEC ops.usp_RestoreScript;
GO

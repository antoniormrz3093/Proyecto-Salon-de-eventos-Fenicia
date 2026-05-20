-- Tier 1: conteo de filas + checksum por tabla (detecta INSERT/UPDATE/DELETE en CUALQUIER tabla).
-- Checksum tolerante a fallos (tablas con varbinary(max) -> 'n/a').
SET NOCOUNT ON;
DECLARE @r TABLE (tabla sysname, filas bigint, chk varchar(30));
DECLARE @t sysname, @sql nvarchar(max), @f bigint, @k varchar(30);
DECLARE c CURSOR LOCAL FAST_FORWARD FOR
  SELECT name FROM sys.tables WHERE is_ms_shipped = 0 ORDER BY name;
OPEN c; FETCH NEXT FROM c INTO @t;
WHILE @@FETCH_STATUS = 0
BEGIN
  SET @f = NULL; SET @k = NULL;
  DECLARE @tc TABLE (f bigint); DELETE @tc;
  SET @sql = N'SELECT COUNT_BIG(*) FROM [' + @t + N']';
  INSERT @tc EXEC sp_executesql @sql; SELECT TOP 1 @f = f FROM @tc;
  BEGIN TRY
    DECLARE @tk TABLE (k varchar(30)); DELETE @tk;
    SET @sql = N'SELECT CONVERT(varchar(30), CHECKSUM_AGG(BINARY_CHECKSUM(*))) FROM [' + @t + N']';
    INSERT @tk EXEC sp_executesql @sql; SELECT TOP 1 @k = k FROM @tk;
  END TRY BEGIN CATCH SET @k = 'n/a' END CATCH
  INSERT @r VALUES (@t, @f, @k);
  FETCH NEXT FROM c INTO @t;
END
CLOSE c; DEALLOCATE c;
SELECT tabla, filas, ISNULL(chk, 'NULL') AS chk FROM @r ORDER BY tabla;

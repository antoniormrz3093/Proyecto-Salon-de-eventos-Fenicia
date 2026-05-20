-- Programacion a nivel RenglonDePresupuesto. BLOBs de distribucion en hex (style 1 => '0x...').
SET NOCOUNT ON;
SELECT
  RenglonDePresupuestoId            AS Id,
  ClaveDeRenglon                    AS Clave,
  TipoRenglonPresupuesto            AS Tipo,
  Cantidad,
  CantidadProgramada                AS CantProg,
  TotalProgramado                   AS TotProg,
  EstaProgramada                    AS Prog,
  ProgramaSegunRendimiento          AS PorRend,
  CantidadesDistribuidas            AS Distr,
  DistribucionesEditadas            AS DistEdit,
  DiasCalendario                    AS DiasCal,
  CONVERT(varchar(19), FechaInicio, 120) AS FIni,
  CONVERT(varchar(19), FechaFin, 120)    AS FFin,
  TiempoInicioMasTemprano           AS TTemprano,
  TiempoInicioMasTardio             AS TTardio,
  CONVERT(varchar(max), DistribucionSemanal, 1)   AS DSem,
  CONVERT(varchar(max), DistribucionQuincenal, 1) AS DQuin,
  CONVERT(varchar(max), DistribucionMensual, 1)   AS DMen,
  CONVERT(varchar(max), InterrupcionesFechas, 1)  AS IntFch
FROM RenglonDePresupuesto
ORDER BY RenglonDePresupuestoId;

-- Programacion a nivel Actividad (entidad paralela, mas rica: incluye CantidadesPorDia).
SET NOCOUNT ON;
SELECT
  ActividadId                       AS Id,
  ClaveDeRenglon                    AS Clave,
  TipoRenglonPresupuesto            AS Tipo,
  Cantidad,
  CantidadProgramada                AS CantProg,
  EstaProgramada                    AS Prog,
  ProgramaSegunRendimiento          AS PorRend,
  CantidadesDistribuidas            AS Distr,
  DiasCalendario                    AS DiasCal,
  DiasTrabajables                   AS DiasTrab,
  CONVERT(varchar(19), FechaInicio, 120) AS FIni,
  CONVERT(varchar(19), FechaFin, 120)    AS FFin,
  CONVERT(varchar(max), CantidadesPorDia, 1)      AS CxDia,
  CONVERT(varchar(max), DistribucionSemanal, 1)   AS DSem,
  CONVERT(varchar(max), DistribucionQuincenal, 1) AS DQuin,
  CONVERT(varchar(max), DistribucionMensual, 1)   AS DMen,
  CONVERT(varchar(max), Interrupciones, 1)        AS Int1,
  CONVERT(varchar(max), InterrupcionesFechas, 1)  AS IntFch,
  ProyectoId, ActividadPadreId      AS PadreId
FROM Actividad
ORDER BY ActividadId;

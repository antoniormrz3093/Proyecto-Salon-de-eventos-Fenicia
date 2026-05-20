-- Parametros globales del programa de obra + calendario.
SET NOCOUNT ON;
SELECT
  CONVERT(varchar(19), FechaInicioProgramaDeObra, 120) AS FIniPrograma,
  CONVERT(varchar(19), FechaFinProgramaDeObra, 120)    AS FFinPrograma,
  InicioDeSemana,
  SincronizarFechasProyectoConProgramaDeObra           AS Sincr,
  TipoCorrimientoFechas                                AS Corrimiento,
  PeriodoPrimeraEstimacion                             AS Per1aEst
FROM ProyectoPropuesta;

SELECT CalendarioId, HorasTrabajables, CONVERT(varchar(19), HoraInicioLabores, 120) AS HoraIni
FROM Calendario ORDER BY CalendarioId;

SELECT UnidadDeTrabajoId AS Id, TipoUnidad, CalendarioId AS CalId, DiaDeSemana AS Dia,
       CONVERT(varchar(19), FechaInicio, 120) AS FIni, CONVERT(varchar(19), FechaFin, 120) AS FFin,
       CONVERT(varchar(max), HorariosDeTrabajo, 1) AS Horarios
FROM UnidadDeTrabajo ORDER BY UnidadDeTrabajoId;

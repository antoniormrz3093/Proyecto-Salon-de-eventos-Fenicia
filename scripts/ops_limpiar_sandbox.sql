-- Limpia el sandbox: revierte programacion de prueba al estado pristino de la 110.
-- NO toca UnidadDeTrabajo (se conserva el calendario). Commit solo si queda 0 programados / 0 vinculos.
SET XACT_ABORT ON;
SET NOCOUNT ON;
BEGIN TRAN;

DELETE FROM [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\COPIA DE 110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.Vinculo;

UPDATE s SET
  s.EstaProgramada=p.EstaProgramada, s.ProgramaSegunRendimiento=p.ProgramaSegunRendimiento,
  s.CantidadProgramada=p.CantidadProgramada, s.Remanente=p.Remanente, s.TotalProgramado=p.TotalProgramado,
  s.UEjecutoras=p.UEjecutoras, s.CantidadesDistribuidas=p.CantidadesDistribuidas, s.DistribucionesEditadas=p.DistribucionesEditadas,
  s.DiasCalendario=p.DiasCalendario, s.DiasTrabajables=p.DiasTrabajables, s.Esfuerzo=p.Esfuerzo,
  s.FechaInicio=p.FechaInicio, s.FechaInicioOriginal=p.FechaInicioOriginal, s.FechaFin=p.FechaFin,
  s.CantidadesPorDia=p.CantidadesPorDia, s.DistribucionSemanal=p.DistribucionSemanal,
  s.DistribucionQuincenal=p.DistribucionQuincenal, s.DistribucionMensual=p.DistribucionMensual,
  s.Interrupciones=p.Interrupciones, s.InterrupcionesFechas=p.InterrupcionesFechas,
  s.TiempoInicioMasTemprano=p.TiempoInicioMasTemprano, s.TiempoInicioMasTardio=p.TiempoInicioMasTardio
FROM [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\COPIA DE 110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.RenglonDePresupuesto s
JOIN [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.RenglonDePresupuesto p
  ON s.RenglonDePresupuestoId = p.RenglonDePresupuestoId
WHERE s.EstaProgramada=1 OR s.CantidadProgramada<>0 OR s.DistribucionesEditadas=1;

UPDATE s SET
  s.FechaInicioFinanciamiento=p.FechaInicioFinanciamiento, s.FechaFinFinanciamiento=p.FechaFinFinanciamiento,
  s.FechaInicioProyecto=p.FechaInicioProyecto, s.FechaFinProyecto=p.FechaFinProyecto,
  s.FechaInicioProgramaDeObra=p.FechaInicioProgramaDeObra, s.FechaFinProgramaDeObra=p.FechaFinProgramaDeObra,
  s.FechaDeInicio=p.FechaDeInicio, s.FechaDeTermino=p.FechaDeTermino
FROM [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\COPIA DE 110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.ProyectoPropuesta s
CROSS JOIN [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.ProyectoPropuesta p;

DECLARE @prog int =(SELECT COUNT(*) FROM [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\COPIA DE 110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.RenglonDePresupuesto WHERE EstaProgramada=1);
DECLARE @vin int  =(SELECT COUNT(*) FROM [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\COPIA DE 110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.Vinculo);
DECLARE @cprog int=(SELECT COUNT(*) FROM [C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\COPIA DE 110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF].dbo.RenglonDePresupuesto WHERE CantidadProgramada<>0);

IF @prog=0 AND @vin=0 AND @cprog=0
  BEGIN COMMIT; SELECT 'COMMIT' AS estado, @prog AS programados, @vin AS vinculos, @cprog AS conCantProg; END
ELSE
  BEGIN ROLLBACK; SELECT 'ROLLBACK' AS estado, @prog AS programados, @vin AS vinculos, @cprog AS conCantProg; END

-- Dependencias del Gantt (texto plano, decodificable directo).
-- TipoVinculo: por confirmar (tipico 0=FF? / FS / SS / SF). Aplazamiento = lag/lead.
SET NOCOUNT ON;
SELECT Oid, RenglonInicioId AS Inicio, RenglonFinId AS Fin,
       TipoVinculo AS Tipo, Aplazamiento AS Lag, CadenaAplazamiento AS LagTxt
FROM Vinculo
ORDER BY Oid;

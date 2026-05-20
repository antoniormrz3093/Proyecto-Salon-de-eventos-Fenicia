# Proyecto Salón de Eventos — Centro Libanés — FENICIA Proy y Cons

Salón de eventos en el Centro Libanés, CDMX. Desarrollador: FENICIA Proy y Cons.

---

## DATOS DE ESTE PROYECTO (completar antes de invocar skills OPUS)

> Las skills `opus-*` leen estos campos. Si están como `<PENDIENTE>`, las skills se detendrán y pedirán completarlos.

- **Server LocalDB**: `(localdb)\OpusLocal`
- **Ruta MDF original**: `C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF`
- **Ruta MDF COPIA**: `No aplica — se opera sobre la MDF original`
- **Nombre exacto de la BD registrada** (en MAYÚSCULAS, como aparece en `sys.databases`): `C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF`
- **Carpeta de salida Excels CLAUDE**: `<ruta del repo>\salidas\`
- **Carpeta de backups**: `<ruta del repo>\backups\`
- **Carpeta de bitácora**: `<ruta del repo>\bitacora\`
- **Tarifas MO** (defaults CDMX Q2-2026, sobreescribir si difiere):
  - Oficial: $620 / jornada
  - Ayudante: $420 / jornada
  - Cuadrilla: $1,040 / jornada
- **Tarifas objetivo por disciplina** (cuando el usuario las dicte): `<PENDIENTE>`

> **Política de seguridad de escritura para ESTE proyecto**: se opera **sobre la MDF original** (no hay copia). Por lo tanto, **backup `.bak` con timestamp es OBLIGATORIO antes de cada escritura**, además de cerrar OPUS / KILL sesiones + transacción explícita + verificación post-commit + bitácora.

---

## Contexto OPUS Módulo 1

OPUS Módulo 1 = "Presupuesto Programable" (presupuesto puro, sin EVM). Distinto de Módulo 2.

- **Engine**: SQL Server 2019 Express (LocalDB v904). NO usar `OpusLocalM2` (Módulo 2, SQL 2014, falla con "version 904 not supported").
- **Conexión**: las BDs se registran con su **ruta MDF completa en MAYÚSCULAS** como nombre de BD. Listarlas con:
  ```bash
  sqlcmd -S "(localdb)\OpusLocal" -E -Q "SELECT name FROM sys.databases"
  ```
- **No existen aquí** (son de Módulo 2): `PlanDeEjecucion`, `Avance`, `EntidadDesglosable`, `VistaCostosTarea`.

### Tablas clave de Módulo 1

| Tabla | Uso |
|---|---|
| `ProyectoPropuesta` | Header del proyecto, `Importe` = total presupuesto |
| `Concepto` | Catálogo de conceptos |
| `RenglonDePresupuesto` | Renglones. `TipoRenglonPresupuesto=2` = renglón normal. `ClaveDeRenglon`, `Descripcion`, `UnidadMedida`, `Cantidad`, `PrecioUnitario` |
| `Recurso` | Recursos. Descripción mostrada en matrices de PU. Link: `RenglonDePresupuesto.RecursoConceptoId = Recurso.RecursoId` |
| `MatrizDeRecursos`, `RecursoComponente` | Matrices de PU y sus componentes |
| `Material`, `ManoDeObra`, `Equipo`, `CostoHorario` | Recursos por tipo |
| `HojaDePresupuesto` | `ImporteTotal` = total del encabezado (NO se calcula del árbol al vuelo) |
| `Indirecto`, `Sobrecosto` | Indirectos y sobrecosto |

### Encoding al consultar OPUS

- `sqlcmd` default → `cp850` (rompe ñ/acentos).
- LEER con acentos: `sqlcmd ... -u -o archivo.txt` (UTF-16LE).
- ESCRIBIR: archivo `.sql` en UTF-8 con BOM + `sqlcmd -i archivo.sql -f 65001`. O pyodbc con parámetros.
- No truncar descripciones largas: `-y 0 -Y 0`.

---

## Skills OPUS disponibles

| Skill | Cuándo invocarla |
|---|---|
| `/opus-conectar` | Verificar conexión, descubrir nombre exacto de la BD, sanity check |
| `/opus-analisis-pu` | Cotizar PU=0, generar Excel re-importable a OPUS |
| `/opus-ortografia-comparativa` | Revisión ortográfica solo-reporte (Excel comparativo, sin tocar BD) |
| `/opus-ortografia-escritura` | Aplicar correcciones ortográficas directo a la BD, con backup + transacción + bitácora |
| `/opus-escritura-segura` | **Cualquier escritura estructural** (crear conceptos, replicar matrices, insertar/editar recursos, borrar renglones). Cubre el protocolo completo + todas las trampas de OPUS |
| `/opus-programa` | **Generar programa de obra**: programar renglones (distribución + fechas + esfuerzo) en modos duración/rendimiento, con vínculos FS/SS. Sincroniza encabezado. Los reportes derivados (suministros/MO/materiales/erogaciones) salen de la distribución × matriz de PU |

---

## Convenciones de trabajo

- **Análisis de PU NO incluye** (salvo que el proyecto lo indique): indirectos, financiamiento, utilidad, IVA. Solo costo directo (Material + MO + Herramienta menor).
- **Herramienta menor** = 3% de MO (5% si es herrería con soldadura).
- **Antes de cualquier escritura a BD**: cerrar OPUS / KILL sesiones + backup `.bak` con timestamp + transacción explícita + verificación post-commit + bitácora.

---

## Estructura del repo

```
<repo>/
├── CLAUDE.md            ← este archivo
├── README.md
├── salidas/             ← Excels generados
├── backups/             ← .bak previos a cada escritura
├── bitacora/            ← bitácoras Excel de cambios aplicados
└── scripts/             ← scripts ad-hoc del proyecto
```

---

## Modelo de Programación (Programa de Obra) — en desarrollo

> Skill nueva en construcción: generar **programa de obra** y derivados (suministros, MO, maquinaria, erogaciones). Reverse-engineering por observación de deltas. Estado: modelo mapeado, decodificación de BLOBs resuelta.

### Tablas de programación

| Tabla | Rol |
|---|---|
| `RenglonDePresupuesto` | Programación por concepto (fechas, duración, distribución). PK `RenglonDePresupuestoId` |
| `Actividad` | Entidad paralela más rica (incluye `CantidadesPorDia`, `ActividadPadreId`). Relación con Renglón: por confirmar |
| `Vinculo` | Dependencias del Gantt (texto plano). `RenglonInicioId`→`RenglonFinId`, `TipoVinculo`, `Aplazamiento` (lag) |
| `Calendario` | `HorasTrabajables` (en ticks: `288000000000` = 8 h), `HoraInicioLabores` |
| `UnidadDeTrabajo` | Horarios laborables por `DiaDeSemana`; `HorariosDeTrabajo` = BLOB |
| `ProyectoPropuesta` | Fechas globales: `FechaInicioProgramaDeObra`/`Fin`, `InicioDeSemana`, sincronización |

### Campos clave en `RenglonDePresupuesto`
`EstaProgramada`(bit), `FechaInicio`/`FechaFin`/`FechaInicioOriginal`, `DiasCalendario`, `CantidadProgramada`, `TotalProgramado`, `ProgramaSegunRendimiento`(bit), `CantidadesDistribuidas`/`DistribucionesEditadas`(bit), `TiempoInicioMasTemprano`/`MasTardio`(float, holguras CPM).

### ⚙️ Codificación de los BLOBs `varbinary` (RESUELTO)
Son objetos **.NET `BinaryFormatter`** de **tipos del framework** (deserializables/serializables sin ensamblados de OPUS, en Windows PowerShell 5.1):

- `DistribucionSemanal` / `DistribucionQuincenal` / `DistribucionMensual` = **`Dictionary<DateTime, Decimal>`** (fecha de inicio de periodo → cantidad de ese periodo).
- `UnidadDeTrabajo.HorariosDeTrabajo` = `HashSet<ValueTuple<DateTime,DateTime>>` (rangos horarios laborables).
- `Actividad.CantidadesPorDia` / `Interrupciones` / `InterrupcionesFechas` = por confirmar (probablemente `Dictionary<DateTime,Decimal>` y sets de tuplas de fechas).

### Dashboard HTML para el cliente (`scripts/opus-dashboard.ps1`)
Genera un HTML autocontenido del programa de obra (tabla por capítulo + barras Gantt por mes + **un campo de observaciones editable por concepto**). El destinatario escribe comentarios → autoguardado en su navegador (localStorage) + botón **"Descargar HTML con comentarios"** que incrusta las observaciones en un archivo nuevo para reenviar (también exporta CSV). Uso: `opus-dashboard.ps1 -Database "<mdf>" -Salida "<ruta.html>"`. Entregable generado en `02 ENTREGABLES\REV 04\06 PROGRAMA DE OBRA\`.

### 🧰 Toolkit (`scripts/`)
- `opus-snapshot.ps1 -Label <x> -Database "<mdf>"` → foto del estado a `scripts/snapshots/<x>/` (BLOBs en hex; usa `-y0 -Y0`, NO `-W`).
- `opus-diff.ps1 -Before <a> -After <b>` → muestra filas/tablas que cambiaron entre dos fotos.
- `opus-decode-blob.ps1 -Database "<mdf>" -Query "SELECT col FROM ..."` → deserializa un BLOB y lista su contenido.
- Templates en `scripts/sql/`: `00_tables` (checksum por tabla), `10_renglon`, `20_actividad`, `30_vinculo`, `40_proyecto`.

### EXP01 — Programación por rendimiento (decodificado)
Acción: concepto `DEM` (cant 126), `ProgramaSegunRendimiento=ON`, `UEjecutoras=5`, inicio 20-may-2026. OPUS calculó duración.

**Diff de TODA la BD (solo estas tablas cambian):** `RenglonDePresupuesto`, `ProyectoPropuesta`, `UnidadDeTrabajo`, `hibernate_unique_key`, + UI (`ColumnPresentation`/`ControlPresentation`). **NO cambian** `Material`, `ManoDeObra`, `Equipo`, `MatrizDeRecursos`, `Indirecto`, `HojaDePresupuesto`, `Estimacion`, `Actividad`, `Vinculo`.

**Campos que cambian en `RenglonDePresupuesto` (17):**
| Campo | Antes→Después | Significado / a qué reporte alimenta |
|---|---|---|
| `EstaProgramada` | F→T | marca programado |
| `ProgramaSegunRendimiento` | F→T | técnica usada |
| `UEjecutoras` | 1→5 | unidades ejecutoras (driver de duración) |
| `CantidadProgramada` | 0→126 | cantidad programada |
| `Remanente` | 126→0 | cantidad sin programar (= Cantidad − CantidadProgramada) |
| `TotalProgramado` | 0→56289.24 | importe (= 126 × PU) → **programa de erogaciones/montos** |
| `DiasCalendario` | 0→10 | días naturales del lapso |
| `DiasTrabajables` | 0→8.399916 | días hábiles (según calendario; <DiasCalendario por findes/festivos) |
| `Esfuerzo` | 0→67.199329 | horas-hombre/trabajo (= DiasTrabajables × 8h) → **programa de MO** |
| `FechaInicio`/`FechaInicioOriginal` | →2026-05-20 08:00 | inicio |
| `FechaFin` | →2026-05-29 15:11:57 | fin (datetime exacto, día parcial) |
| `CantidadesDistribuidas` | F→T | tiene distribución |
| `CantidadesPorDia` | blob vacío→lleno | `Dictionary<DateTime,Decimal>` por DÍA |
| `DistribucionSemanal/Quincenal/Mensual` | blob vacío→lleno | `Dictionary<DateTime,Decimal>` por periodo |

**Distribución (clave=fecha ancla del periodo, valor=cantidad):** reparto **proporcional a las horas laborables** de cada periodo según el calendario.
- Semanal: ancla = **domingo** (`InicioDeSemana=0`). Ej: 17-may→52.5, 24-may→73.5.
- Quincenal: anclas **día 1 y 16** del mes (16-may→126).
- Mensual: ancla **día 1** (01-may→126). Suma = `CantidadProgramada`.

**Sincronización de encabezado (`ProyectoPropuesta`):** al fijar el programa, las fechas se **propagan** (flags Sincronizar): `FechaInicioProgramaDeObra/Fin`, `FechaInicioProyecto/Fin`, `FechaDeInicio/Termino`, **`FechaInicioFinanciamiento/Fin`**. → de aquí salen **indirectos y financiamiento** (se recalculan on-demand leyendo estas fechas; la tabla `Indirecto` no se reescribe en la acción).

**Modelo de calendario (`UnidadDeTrabajo`):**
- `TipoUnidad='Dia'`: plantilla semanal, `DiaDeSemana` 1=Lun…6=Sáb, **0=Dom**. `HorariosDeTrabajo`=`HashSet<ValueTuple<DateTime,DateTime>>` (rangos horarios; solo importa la hora). Día completo = 09:00–14:00 + 15:00–18:00 (8h). No laborable = set vacío (`DATALENGTH≈1187`).
- `TipoUnidad='Rango'`: **excepción por fecha** (`FechaInicio=FechaFin=día`). Sáb medio = 08:00–12:00 (4h, `len≈1896`); festivo = set vacío (`len≈1187`). OPUS materializa una `Rango` por cada fecha-excepción del horizonte.

**Conclusión para los reportes derivados:** *programa de suministros / utilización de materiales / MO* **no se almacenan**: se calculan = distribución del concepto × coeficientes de la matriz de PU. Basta con que la skill escriba bien `CantidadProgramada`, `TotalProgramado`, `Esfuerzo`/`DiasTrabajables`, las 4 distribuciones y sincronice las fechas del encabezado.

### EXP02 — Programación por duración (inicio + días calendario)
Acción: concepto `010822` (cant 78.75), `ProgramaSegunRendimiento=OFF`, inicio 20-may, 6 días calendario. OPUS calculó fin.

**Diff de TODA la BD:** SOLO cambia `RenglonDePresupuesto`. **`ProyectoPropuesta` NO cambia** porque el lapso (20→25-may) cae dentro de la ventana ya fijada por DEM. → **El encabezado solo se sincroniza cuando el programa se EXTIENDE** más allá del envelope actual.

**Diferencias vs EXP01 (rendimiento):** `ProgramaSegunRendimiento` queda **False**, `UEjecutoras` **no cambia** (1). Los demás campos cambian igual que EXP01 (distribuciones, `CantidadProgramada`, `TotalProgramado`=cant×PU, `Esfuerzo`=DiasTrab×8, `DiasCalendario`, `DiasTrabajables`, fechas, `EstaProgramada`, `CantidadesDistribuidas`).

**`CantidadesPorDia` (driver fino, `Dictionary<DateTime,Decimal>` por día):** tasa diaria constante en días completos, **mitad** en sábado a medias, **0** (con clave presente) en no laborables. Ej. 010822: 20–22-may=17.5, 23-may(sáb)=8.75, 24-may(dom)=0, 25-may=17.5. Suma=78.75. Las distribuciones Semanal/Quincenal/Mensual son **agregaciones** de `CantidadesPorDia` por ancla de periodo.
- Nota: aun en modo "por duración", si el concepto tiene rendimiento de cuadrilla OPUS puede ajustar la duración a cantidad÷rendimiento (verificar caso sin rendimiento).

### EXP03 — Extender el envelope + multi-mes
Acción: a `010822` se le dio 36 días calendario (27 trabajables), saliéndose del rango de DEM.

- **Sincronización de encabezado confirmada:** envelope = `[min(FechaInicio), max(FechaFin)]` de los conceptos programados. Al extender el fin a 24-jun 16:00, se recorrieron las 10 fechas: `FechaFin{ProgramaDeObra,Proyecto,Financiamiento}`, `FechaDeTermino` → 24-jun; inicios quedan en el más temprano (20-may). **`Indirecto` NO se reescribe** (recalcula on-demand desde estas fechas).
- **"Por duración" honra la duración:** tasa diaria = cantidad ÷ `DiasTrabajables` (78.75/27 = 2.9167/día). `DiasCalendario` y `DiasTrabajables` los pone el usuario / calendario.
- **Multi-periodo:** `DistribucionMensual` = 1 entrada por mes (ancla día 1) = suma de los días de ese mes (01-may→26.24, 01-jun→52.51). Igual lógica para semanal/quincenal.

### EXP05 — Vínculos / dependencias (`Vinculo`) decodificado
Mismo par DEM→010822, variando el tipo.

- **`RenglonInicioId` = predecesora**, **`RenglonFinId` = sucesora**.
- **`TipoVinculo`**: `0`=FS (Fin→Comienzo), `1`=FF (Fin→Fin), `2`=SS (Comienzo→Comienzo), `3`=SF (Comienzo→Fin).
- **`Aplazamiento`** = lag en **horas laborables** (3 días lab. = 24). **`CadenaAplazamiento`** = texto con signo y unidad, ej. `+3l` (`l`=días laborables).
- **Crear/editar un vínculo REPROGRAMA a la sucesora** (no solo inserta fila): recalcula sus fechas (FS: inicio sucesora = fin predecesora + lag, al segundo), sus distribuciones, y extiende el envelope del encabezado. → Si la skill escribe vínculos, debe recalcular en cascada o dejar que OPUS lo haga al abrir.

### EXP04 — Reparto manual (`DistribucionesEditadas=1`)
Acción: `TR01` (cantidad total 28.51), editado a escala **mensual**: Abr, May=10, Jun=5, Jul=8.51.

- **`DistribucionesEditadas=1`** marca edición manual.
- **La escala editada manda; las escalas finas se RECALCULAN** desde ella: cada bucket (mes) se reparte hacia quincena/semana/día **proporcional a las horas laborables** dentro de ese bucket; los buckets finos que cruzan el límite del bucket grueso se prorratean. (Mensual=valores manuales; quincenal=2 por mes; semanal=18 semanas; suma por mes respetada.)
- **Las fechas se expanden** para abarcar todos los periodos con cantidad: `FechaInicio`=inicio del primer periodo (01-abr 00:00), `FechaFin`=fin del último (31-jul 23:00), `DiasCalendario`/`DiasTrabajables` recalculados al lapso completo.
- **Valores manuales guardados tal cual** (Abr=5, May=10, Jun=5, Jul=8.51 = 28.51 = `Cantidad` total). La suma del reparto coincidió con la cantidad total → `CantidadProgramada=28.51`, `Remanente=0`. **Pendiente de confirmar:** si OPUS admite reparto parcial (suma < cantidad total) o lo fuerza al total. Por seguridad, el generador hará que la distribución sume `CantidadProgramada`.

### MODELO DE ESCRITURA (consolidado, listo para generar)
Para programar un concepto, escribir en su `RenglonDePresupuesto`:
1. `EstaProgramada=1`, `CantidadesDistribuidas=1`, `CantidadProgramada`=cantidad, `Remanente`=Cantidad−CantidadProgramada.
2. `ProgramaSegunRendimiento` (1 si por rendimiento+`UEjecutoras`; 0 si por duración).
3. `FechaInicio`=`FechaInicioOriginal`=inicio (con hora de calendario, 08:00); `FechaFin`=fin (datetime exacto); `DiasCalendario`, `DiasTrabajables` (según calendario), `Esfuerzo`=DiasTrabajables×8.
4. `TotalProgramado` = **(CantidadProgramada/Cantidad) × `Total`** (columna `Total` del renglón). ⚠ NO usar `Cantidad×PrecioUnitario`: el PU está redondeado y `Total` ≠ `Cantidad×PU` en algunos renglones (ej. ACAPIS01-1 muros, ~$2.79), por lo que el programa no cerraría al 100% contra el presupuesto. Con esto, Σ TotalProgramado = total del presupuesto exacto.
5. `CantidadesPorDia`=`Dictionary<DateTime,Decimal>`: cantidad por día hábil a tasa constante (mitad en días a medias, 0 en no laborables, con clave presente). Tasa=Cantidad÷DiasTrabajables.
6. `DistribucionSemanal/Quincenal/Mensual`=agregaciones de CantidadesPorDia por ancla (semana=domingo si `InicioDeSemana=0`; quincena=día 1 y 16; mes=día 1). Serializar como BinaryFormatter.
7. Encabezado `ProyectoPropuesta`: recalcular envelope `[min inicio, max fin]` y propagar a las 10 fechas sincronizadas.
8. Calendario `UnidadDeTrabajo`: filas `Dia` (plantilla) + `Rango` (excepciones por fecha). Para la distribución hay que LEER el calendario y contar horas laborables por día.

Pendiente de decodificar: distribución **editada a mano** (`DistribucionesEditadas=1`), tabla `Vinculo` (dependencias), relación con `Actividad` (no se toca al programar renglones → posiblemente espejo de Módulo 2, irrelevante para esto).

### Motor de programación VALIDADO (scripts/opus-schedule-engine.ps1) — EXP06
- Serialización `Dictionary<DateTime,Decimal>` desde cero = OPUS-compatible (round-trip idéntico salvo 1 byte = contador `_version`, inofensivo).
- **Reloj calibrado (EXP06):** la jornada arranca a `Calendario.HoraInicioLabores` (08:00); un día = sus horas del calendario **contiguas desde 08:00, SIN descontar comida** (8h→16:00 entre semana; 4h→12:00 sábado a medias; 0 no laborable). El último día (o el primero, si inicia a media jornada por un vínculo) puede ser **parcial**.
- **Algoritmo:** acumular `Esfuerzo` horas (=`DiasTrabajables`×8) desde `FechaInicio`, día a día tomando `min(horasDisponiblesDia, restante)`; cantidad del día = `Cantidad × horasUsadasDia / Esfuerzo`; `FechaFin` = 08:00 + horas usadas en el último día.
- **Validado EXACTO** (fecha al segundo, cantidad al centavo) contra K-1/D-01/RES-01 (duración) y DEM (rendimiento, con sábado a medias y último día parcial → 15:11:57). 
- **Rendimiento (VALIDADO):** `DiasTrabajables = Cantidad / (Rend × UEjecutoras)`, donde `Rend` = `RecursoComponente.Rendimiento` del componente con `DefineRendimientoActividad=1` (la cuadrilla) en la matriz del concepto (`MatrizDeRecursosId = RenglonDePresupuesto.RecursoConceptoId`). `Esfuerzo = DiasTrab × 8`. Verificado exacto contra DEM (rend 3.00003, 5 cuad → 8.4 dtrab → fin 29-may 15:11:57). **Conceptos sin componente definidor** (ej. HERR01, D-01) NO se pueden programar por rendimiento → solo duración. Para **duración**: `Esfuerzo` = Σ horas laborables sobre los `DiasCalendario` días del lapso.
- **IMPORTANTE — clave de operación:** el generador opera por **`RenglonDePresupuestoId`** (PK único). `ClaveDeRenglon` puede repetirse (en este proyecto: ACAPIS01, ACAPIS01-1).

### Orden del catálogo (selección de renglones)
`Indice` es el orden **entre hermanos por nivel**, NO el orden global. Para "primeros N en orden de catálogo" hay que **recorrer el árbol** (`RenglonPadreId` → hijos por `Indice`, recursivo). CTE recursivo construyendo un `sortkey` de índices concatenados y `ORDER BY sortkey`. El generador debe seleccionar así (y operar por `RenglonDePresupuestoId`).

### Generador VALIDADO en OPUS (2026-05-19)
Se programaron 5 conceptos con `scripts/opus-program.ps1` y **OPUS abrió el proyecto sin error**, mostrando barras Gantt, distribuciones y reportes derivados correctos. → El camino de escritura (serialización de BLOBs + campos + sincronización de encabezado) es **100% compatible con OPUS**. (Nota: la selección de esos 5 fue por `Indice` plano, no el orden real de árbol; el motor de escritura es correcto.)

### Estado / hallazgos
- 110: 132 renglones con diccionarios de distribución **presentes pero vacíos** → la obra **NO está programada** aún. `Vinculo` vacío (0 dependencias).
- Derivados (suministros/MO/maquinaria/erogaciones): probablemente **no se almacenan**; OPUS los calcula = distribución por periodo × coeficientes de la matriz de PU. La skill los replicará.

### Sandbox de experimentación
`C:\ECOSOFT\PROYECTOS\PRESUPUESTO PROGRAMABLE\COPIA DE 110 CENTRO LIBANES_ SALONES DE EVENTOS.MDF` (idéntico a la 110 al crearse: 132 renglones, 0 programados, 0 vínculos). Todos los experimentos de programación se hacen aquí.

### Roadmap de la skill
1. ✅ Crear **sandbox** (copia del proyecto vía OPUS) para experimentar sin tocar la 110.
2. ✅ EXP01 (rendimiento), EXP02 (duración), EXP03 (envelope + multi-mes), EXP04 (reparto manual) decodificados. **Modelo de lectura COMPLETO.**
3. ✅ EXP05: `Vinculo` decodificado (tipos 0=FS,1=FF,2=SS,3=SF; lag en horas laborables; reprograma sucesora en cascada).
4. ✅ `Actividad` NO se toca al programar renglones (espejo de Módulo 2, irrelevante). `CantidadesPorDia` decodificado.
5. ✅ Generador (`scripts/opus-program.ps1`) modos **DURACIÓN** (validado OPUS) y **RENDIMIENTO** (validado exacto vs DEM) + **VÍNCULOS FS/SS** con cascada (lag en horas laborables, `AddWorkHours`/`NormStart`, scheduling iterativo por dependencias, INSERT en `Vinculo` con Oid=MAX+1). Cascada **VALIDADA en OPUS** (FS, lag 0 y +2d). Pendiente menor: FF/SF (derivan el fin), selección por orden de árbol. CSV: `Id,FechaInicio,Modo,DiasCalendario,UEjecutoras,PredId,TipoVinc,LagDias`.
6. ✅ Empaquetada la skill **`/opus-programa`** (`C:\Users\12700H\.claude\skills\opus-programa\` con SKILL.md + scripts opus-program/decode-blob/schedule-engine/calendario/csa/dashboard).
7. ✅ Programa COMPLETO escrito en la copia (107 conceptos + CSA, ~6.4 meses, cierra al 100% del presupuesto) según la lógica dictada por el usuario. Calendario extendido (sábados a medias + festivos LFT). Falta validar fino y replicar en la 110 original.
8. ✅ **Dashboard HTML para el cliente** (`scripts/opus-dashboard.ps1`) con identidad **SOLINGEN** (ver memoria `solingen-brand`): 3 pestañas (Procedimiento Constructivo, Programa de Obra con Gantt+observaciones+vínculos, tabla de Vínculos), colapsables, descripciones cortas, siglas FC/CC/FF/CF. Entregable en `02 ENTREGABLES\REV 04\06 PROGRAMA DE OBRA\`.
9. ⬜ Reportes derivados (suministros, MO, maquinaria, erogaciones) a Excel. ⬜ FF/SF + selección por orden de árbol en el generador. ⬜ Replicar programa en 110 original (con backup).

## PRÓXIMA SESIÓN — prueba de programación de TODO el catálogo

Plan del usuario: programar el catálogo completo según **ciertas instrucciones** (a dictar), **primero en el sandbox** (`COPIA DE 110...`); si sale bien, **replicar en la 110 original** (con backup `.bak` obligatorio).

Antes de correr, definir/confirmar con el usuario:
1. **Instrucciones de programación**: ¿por duración o rendimiento por concepto/capítulo? ¿secuencia con vínculos (FS encadenado por capítulo) o fechas/duraciones dadas? ¿UEjecutoras por disciplina? Construir el CSV (`Id,FechaInicio,Modo,DiasCalendario,UEjecutoras,PredId,TipoVinc,LagDias`) a partir de eso, seleccionando renglones T2 por **orden de árbol** (CTE recursivo, ver sección "Orden del catálogo").
2. **Calendario por horizonte**: extender en OPUS las excepciones de sábado a medias (y festivos) a TODO el horizonte del programa antes de generar, o el motor tomará sábados fuera de mayo como no laborables.
3. **Conceptos sin rendimiento** (sin componente `DefineRendimientoActividad=1`): solo por duración (el script lanza error si se pide REND).
4. Correr `-WhatIf` primero, revisar con el usuario, luego escribir. Verificar y **pedir abrir OPUS**.
5. Para la 110 original: backup `.bak` obligatorio, OPUS cerrado, transacción (el script lo hace). Registrar aquí.

Skill lista: **`/opus-programa`** (en `C:\Users\12700H\.claude\skills\opus-programa\`). Sandbox actualmente tiene programada la cadena TR01→K-1→D-01 (limpiar con `scripts/ops_limpiar_sandbox.sql` antes de la prueba completa).

## Historial de operaciones a BD

> Registrar aquí cada escritura: fecha, qué cambió, backup, bitácora, lecciones. (Ver ejemplos en otros repos OPUS.)

- **2026-05-19 — Programa de obra COMPLETO + CSA (copia).** 107 conceptos T2 (todo el catálogo) programados según la lógica dictada por el usuario + ajustes de duración (red en `scripts/programa_full.csv`); 100 vínculos; calendario extendido (sábados a medias jun-dic + festivos LFT). **CSA** distribuido como % del costo mensual vía `scripts/opus-csa.ps1` ($1,499,383.72). Importe programado total = **$12,845,065.41 = total presupuesto exacto** (tras ajuste `TotalProgramado=(CantProg/Cant)×Total`). Ventana 25-may→14-nov-2026 (~24.7 sem ≈ 6.4 meses). Backups: `SANDBOX_PRE_PROGRAMA_20260519_*.bak`, `SANDBOX_PRE_CSA_20260519_200410.bak`. **Falta validar en OPUS**; luego replicar en 110 original. Scripts nuevos: `opus-calendario.ps1`, `opus-csa.ps1`.

- **2026-05-19 — Generador con vínculos (cadena FS).** Tras limpiar el sandbox, se programó la cadena TR01→K-1→D-01 (vínculos FS, lag 0 y +2 días lab.) con `scripts/opus-program.ps1` (CSV `scripts/test_vinculos.csv`). Insertó 2 filas en `Vinculo` (Oid=MAX+1) + cascada de fechas. Backup: `backups/SANDBOX_PRE_PROGRAMA_20260519_185409.bak`. **VALIDADO en OPUS** (abre sin error, muestra cascada y dependencias FS correctas).

- **2026-05-19 — PRIMERA escritura del generador (5 actividades).** BD: `COPIA DE 110...`. Programadas ACAPIS05, ACAPLA03, P01, TR01, HERR01 por duración vía `scripts/opus-program.ps1` (+ CSV `scripts/programa_input.csv`). Escribió las 4 distribuciones serializadas + fechas + esfuerzo + sincronización de encabezado (envelope 1-jun→3-jul, `ActualizacionNecesaria=0`). Backup: `backups/SANDBOX_PRE_PROGRAMA_20260519_183342.bak`. Verificado en BD: distribuciones legibles y sumas correctas. **Falta validar abriendo en OPUS.** Nota: sábados de jun/jul quedaron no laborables (excepciones `Rango` solo existían para mayo).

- **2026-05-19 — Limpieza del sandbox.** BD: `COPIA DE 110...`. Se revirtió la programación de prueba (DEM, 010822, TR01 + vínculo + fechas de encabezado) al estado prístino, copiando columnas desde la 110 por `RenglonDePresupuestoId` (cross-DB UPDATE en transacción, commit condicionado a 0 programados/0 vínculos). Calendario conservado. Backup: `backups/SANDBOX_PRE_LIMPIEZA_20260519_182656.bak` (16 MB). Verificado: DEM = 0 dif. vs 110. Script: `scripts/ops_limpiar_sandbox.sql`.

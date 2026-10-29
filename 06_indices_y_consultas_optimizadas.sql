/* =====================================================================================
   ISW-323 Taller de Base de Datos III - Trabajo Final (Caso: BusRD)
   Archivo: 06_indices_y_consultas_optimizadas.sql
   Entregable: E3 - Optimización de Consultas e Indexación (Unidad II)
   =====================================================================================
   INSTRUCCIONES DE PARÁMETROS DEL GRUPO:
   Ajuste la variable @NumeroGrupo con el número de su grupo antes de ejecutar.
   Si el docente asignó un ViajeID específico para C1, colóquelo en @ViajeID_Asignado.
   ===================================================================================== */

USE BusRD;
GO

SET NOCOUNT ON;
GO

/* =====================================================================================
   SECCIÓN 1: DIAGNÓSTICO DE LÍNEA BASE (ANTES DE OPTIMIZAR)
   -------------------------------------------------------------------------------------
   Para capturar las métricas ANTES en un entorno limpio (o deshabilitando índices):
   - C1 original realiza Clustered Index Scan sobre dbo.Boletos (~230,000 filas) porque
     no existe índice por ViajeID y además utiliza NOT IN, lo que obliga a evaluar
     posibles valores nulos o escanear toda la tabla de boletos.
   - C2 original aplica LTRIM(RTRIM(c.Cedula)) = @Cedula, lo cual NO ES SARGABLE
     (Search Argument Able). Aunque exista el constraint UNIQUE de E1 sobre Cedula,
     aplicar funciones sobre la columna impide usar Index Seek y fuerza un Index Scan
     sobre los 50,000 clientes, seguido de un Clustered Index Scan en Boletos y un Sort.
   - C3 original aplica YEAR(b.FechaVenta) = 2025 en el WHERE y MONTH(b.FechaVenta) en
     SELECT/GROUP BY. Aplicar YEAR() sobre la columna FechaVenta rompe la SARGabilidad,
     obligando a escanear los ~230,000 boletos y ~225,000 pagos completo.
   ===================================================================================== */


/* =====================================================================================
   SECCIÓN 2: CREACIÓN DE ÍNDICES SECUNDARIOS (CON IDEMPOTENCIA Y JUSTIFICACIÓN)
   -------------------------------------------------------------------------------------
   NOTA DE COMPATIBILIDAD CON E1 (01_integridad.sql):
   1) En E1.3 se exige unicidad en Clientes.Cedula (UQ_Clientes_Cedula). Si E1 ya lo
      creó, SQL Server ya dispone de un índice único sobre (Cedula). Si no existe, este
      script crea IX_Clientes_Cedula como respaldo para garantizar que el script corra
      sin errores en cualquier escenario.
   2) En E1.4 se exige un índice único filtrado en Boletos(ViajeID, NumeroAsiento)
      WHERE Estado = 'Activo'. Para C1 necesitamos exactamente cubrir la búsqueda de
      asientos ocupados activos de un viaje; además, creamos índices de cobertura para
      C2 y C3 minimizando el impacto de escritura en dbo.sp_VenderBoleto.
   ===================================================================================== */

PRINT '>>> Creando índices de optimización para E3...';
GO

/* -------------------------------------------------------------------------------------
   ÍNDICE 1 (Soporte C1): Cobertura de boletos activos por Viaje y Asiento
   - Columnas clave: (ViajeID, NumeroAsiento)
   - Filtro: WHERE Estado = 'Activo'
   - Justificación: Permite resolver la verificación de asientos ocupados en C1 mediante
     un Index Seek puro de apenas ~1 a 26 filas por viaje (2 lecturas lógicas), sin
     tocar la tabla base (sin Key Lookup). Además, si E1 ya creó el índice único filtrado
     sobre estas mismas columnas, verificamos su existencia para evitar índices duplicados
     que penalicen a sp_VenderBoleto.
   ------------------------------------------------------------------------------------- */
IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID('dbo.Boletos')
      AND i.has_filter = 1
      AND EXISTS (
          SELECT 1
          FROM sys.index_columns ic
          JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
          WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id
            AND ic.key_ordinal = 1 AND c.name = 'ViajeID'
      )
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX IX_Boletos_ViajeID_NumeroAsiento_Activo
    ON dbo.Boletos (ViajeID, NumeroAsiento)
    WHERE Estado = 'Activo';
    PRINT 'Creado: IX_Boletos_ViajeID_NumeroAsiento_Activo';
END
ELSE
BEGIN
    PRINT 'Nota: Ya existe un índice filtrado en dbo.Boletos(ViajeID, NumeroAsiento) creado en E1. Se reutiliza para C1.';
END
GO

/* -------------------------------------------------------------------------------------
   ÍNDICE 2 (Soporte C2): Respaldo de búsqueda por Cédula en Clientes
   - Columnas clave: (Cedula) INCLUDE (Nombre, Apellido)
   - Justificación: Si E1 creó UQ_Clientes_Cedula, el motor hace Index Seek + 1 solo
     Key Lookup (para 1 cliente). Con INCLUDE (Nombre, Apellido) eliminamos incluso ese
     Key Lookup, logrando un Index Seek 100% cubierto (2 lecturas lógicas en Clientes).
   ------------------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Clientes') AND name = 'IX_Clientes_Cedula_Covering')
    DROP INDEX IX_Clientes_Cedula_Covering ON dbo.Clientes;
GO
CREATE NONCLUSTERED INDEX IX_Clientes_Cedula_Covering
ON dbo.Clientes (Cedula)
INCLUDE (Nombre, Apellido);
PRINT 'Creado: IX_Clientes_Cedula_Covering';
GO

/* -------------------------------------------------------------------------------------
   ÍNDICE 3 (Soporte C2): Historial de boletos por Cliente
   - Columnas clave: (ClienteID, ViajeID)
   - Columnas incluidas (INCLUDE): (NumeroAsiento, Precio, Estado)
   - Justificación: En C2 se filtra por ClienteID (tras buscar la cédula). Sin este
     índice, SQL Server escanea los ~230,000 boletos para encontrar los ~4 o 5 boletos
     de un cliente. Con (ClienteID, ViajeID) e INCLUDE (NumeroAsiento, Precio, Estado),
     el motor hace un Index Seek directo y obtiene todas las columnas de Boletos sin
     ningún Key Lookup.
   ------------------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Boletos') AND name = 'IX_Boletos_ClienteID_Covering')
    DROP INDEX IX_Boletos_ClienteID_Covering ON dbo.Boletos;
GO
CREATE NONCLUSTERED INDEX IX_Boletos_ClienteID_Covering
ON dbo.Boletos (ClienteID, ViajeID)
INCLUDE (NumeroAsiento, Precio, Estado);
PRINT 'Creado: IX_Boletos_ClienteID_Covering';
GO

/* -------------------------------------------------------------------------------------
   ÍNDICE 4 (Soporte C3): Reporte mensual de ventas activas por rango de FechaVenta
   - Columnas clave: (FechaVenta)
   - Columnas incluidas (INCLUDE): (ViajeID, BoletoID)
   - Filtro: WHERE Estado = 'Activo'
   - Justificación: Al reescribir C3 con un rango SARGable:
     FechaVenta >= '2025-01-01' AND FechaVenta < '2026-01-01' AND Estado = 'Activo',
     este índice filtrado permite hacer un Index Seek por rango sobre FechaVenta solo
     para boletos activos, incluyendo ViajeID (para unir con Viajes/Rutas) y BoletoID
     (para unir con Pagos), eliminando por completo el Clustered Index Scan de Boletos.
   ------------------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Boletos') AND name = 'IX_Boletos_FechaVenta_Activo_Covering')
    DROP INDEX IX_Boletos_FechaVenta_Activo_Covering ON dbo.Boletos;
GO
CREATE NONCLUSTERED INDEX IX_Boletos_FechaVenta_Activo_Covering
ON dbo.Boletos (FechaVenta)
INCLUDE (ViajeID, BoletoID)
WHERE Estado = 'Activo';
PRINT 'Creado: IX_Boletos_FechaVenta_Activo_Covering';
GO

/* -------------------------------------------------------------------------------------
   ÍNDICE 5 (Soporte C3): Cobertura de Pagos por BoletoID y Monto
   - Columnas clave: (BoletoID)
   - Columnas incluidas (INCLUDE): (Monto)
   - Justificación: En C3 se hace JOIN con dbo.Pagos por BoletoID y se calcula SUM(p.Monto).
     La tabla Pagos solo tiene PK en PagoID, por lo que originalmente fuerza un
     Clustered Index Scan de ~225,000 filas. Con este índice cubierto (BoletoID) INCLUDE (Monto),
     el optimizador resuelve el JOIN y la suma leyendo únicamente las páginas hoja del
     índice no agrupado sin tocar la tabla base Pagos.
   ------------------------------------------------------------------------------------- */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID('dbo.Pagos') AND name = 'IX_Pagos_BoletoID_Monto')
    DROP INDEX IX_Pagos_BoletoID_Monto ON dbo.Pagos;
GO
CREATE NONCLUSTERED INDEX IX_Pagos_BoletoID_Monto
ON dbo.Pagos (BoletoID)
INCLUDE (Monto);
PRINT 'Creado: IX_Pagos_BoletoID_Monto';
GO

/* Actualizar estadísticas para asegurar planes de ejecución óptimos */
UPDATE STATISTICS dbo.Clientes WITH FULLSCAN;
UPDATE STATISTICS dbo.Viajes   WITH FULLSCAN;
UPDATE STATISTICS dbo.Boletos  WITH FULLSCAN;
UPDATE STATISTICS dbo.Pagos    WITH FULLSCAN;
GO


/* =====================================================================================
   SECCIÓN 3: VERIFICACIÓN DE EQUIVALENCIA DE RESULTADOS (ORIGINAL VS OPTIMIZADA)
   -------------------------------------------------------------------------------------
   El trabajo final exige comprobar que las consultas reescritas devuelven EXACTAMENTE
   el mismo resultado que las originales. Usamos EXCEPT en ambas direcciones: si ambas
   diferencias devuelven 0 filas, los conjuntos de resultados son 100% idénticos.
   ===================================================================================== */
PRINT '=====================================================================================';
PRINT '>>> VERIFICANDO EQUIVALENCIA EXACTA DE RESULTADOS (ORIGINAL VS OPTIMIZADA)...';
PRINT '=====================================================================================';

DECLARE @NumeroGrupo INT = 1;                  -- <--- CAMBIAR AL NÚMERO DE SU GRUPO (ej. 1, 2, 3...)
DECLARE @ViajeID_C1  INT = 16000;              -- <--- CAMBIAR AL VIAJE ASIGNADO AL GRUPO (ej. 16000 + @NumeroGrupo)
DECLARE @ClienteID_Grupo INT = @NumeroGrupo * 1000;
DECLARE @Cedula_C2 CHAR(11);

SELECT @Cedula_C2 = Cedula
FROM dbo.Clientes
WHERE ClienteID = @ClienteID_Grupo;

-- Si por alguna razón no existe ese ClienteID, usar '40200001000'
IF @Cedula_C2 IS NULL SET @Cedula_C2 = '40200001000';

PRINT 'Parámetros usados -> @ViajeID_C1 = ' + CAST(@ViajeID_C1 AS VARCHAR(20))
    + ' | @ClienteID = ' + CAST(@ClienteID_Grupo AS VARCHAR(20))
    + ' | @Cedula_C2 = ' + @Cedula_C2;

/* --- Comprobación C1 --- */
IF OBJECT_ID('tempdb..#C1_Orig') IS NOT NULL DROP TABLE #C1_Orig;
IF OBJECT_ID('tempdb..#C1_Opt')  IS NOT NULL DROP TABLE #C1_Opt;

-- C1 Original
SELECT s.NumeroAsiento, s.Ubicacion
INTO #C1_Orig
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID_C1
  AND s.NumeroAsiento NOT IN (
      SELECT b.NumeroAsiento
      FROM dbo.Boletos b
      WHERE b.ViajeID = @ViajeID_C1
        AND b.Estado = 'Activo'
  );

-- C1 Optimizada (NOT EXISTS SARGable)
SELECT s.NumeroAsiento, s.Ubicacion
INTO #C1_Opt
FROM dbo.Viajes v
INNER JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID_C1
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.Boletos b
      WHERE b.ViajeID = v.ViajeID
        AND b.NumeroAsiento = s.NumeroAsiento
        AND b.Estado = 'Activo'
  );

SELECT 'Verificación C1 (Diferencias Orig vs Opt)' AS Prueba,
       (SELECT COUNT(*) FROM (SELECT * FROM #C1_Orig EXCEPT SELECT * FROM #C1_Opt) d1) +
       (SELECT COUNT(*) FROM (SELECT * FROM #C1_Opt  EXCEPT SELECT * FROM #C1_Orig) d2) AS FilasDiferentes;


/* --- Comprobación C2 --- */
IF OBJECT_ID('tempdb..#C2_Orig') IS NOT NULL DROP TABLE #C2_Orig;
IF OBJECT_ID('tempdb..#C2_Opt')  IS NOT NULL DROP TABLE #C2_Opt;

-- C2 Original
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
INTO #C2_Orig
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula_C2;

-- C2 Optimizada (Predicado SARGable sin funciones sobre la columna indexada Cedula)
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
INTO #C2_Opt
FROM dbo.Clientes c
INNER JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
INNER JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
INNER JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE c.Cedula = @Cedula_C2;

SELECT 'Verificación C2 (Diferencias Orig vs Opt)' AS Prueba,
       (SELECT COUNT(*) FROM (SELECT * FROM #C2_Orig EXCEPT SELECT * FROM #C2_Opt) d1) +
       (SELECT COUNT(*) FROM (SELECT * FROM #C2_Opt  EXCEPT SELECT * FROM #C2_Orig) d2) AS FilasDiferentes;


/* --- Comprobación C3 --- */
IF OBJECT_ID('tempdb..#C3_Orig') IS NOT NULL DROP TABLE #C3_Orig;
IF OBJECT_ID('tempdb..#C3_Opt')  IS NOT NULL DROP TABLE #C3_Opt;

-- C3 Original
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
INTO #C3_Orig
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE YEAR(b.FechaVenta) = 2025
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);

-- C3 Optimizada (Rango de fechas SARGable sobre FechaVenta)
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
INTO #C3_Opt
FROM dbo.Boletos b
INNER JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
INNER JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
INNER JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.FechaVenta >= '2025-01-01T00:00:00'
  AND b.FechaVenta <  '2026-01-01T00:00:00'
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);

SELECT 'Verificación C3 (Diferencias Orig vs Opt)' AS Prueba,
       (SELECT COUNT(*) FROM (SELECT * FROM #C3_Orig EXCEPT SELECT * FROM #C3_Opt) d1) +
       (SELECT COUNT(*) FROM (SELECT * FROM #C3_Opt  EXCEPT SELECT * FROM #C3_Orig) d2) AS FilasDiferentes;
GO


/* =====================================================================================
   SECCIÓN 4: EJECUCIÓN DE LAS 3 CONSULTAS OPTIMIZADAS CON MÉTRICAS (STATISTICS IO/TIME)
   -------------------------------------------------------------------------------------
   Active "Include Actual Execution Plan" (Ctrl + M) en SSMS al correr esta sección
   para tomar las capturas del plan de ejecución DESPUÉS de la optimización.
   ===================================================================================== */
PRINT '=====================================================================================';
PRINT '>>> EJECUTANDO CONSULTAS OPTIMIZADAS (C1, C2, C3) CON STATISTICS IO Y TIME ON...';
PRINT '=====================================================================================';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

/* -------------------------------------------------------------------------------------
   C1 OPTIMIZADA - Pantalla de taquilla: asientos disponibles de un viaje
   Mejoras aplicadas:
   1. Sustitución de NOT IN por NOT EXISTS correlacionado (semántica segura frente a NULL
      y mejor estimación de cardinalidad con Anti Semi Join).
   2. Aprovecha el índice filtrado en dbo.Boletos(ViajeID, NumeroAsiento) WHERE Estado = 'Activo'.
   3. El ordenamiento por s.NumeroAsiento ya viene dado por el índice PK_Asientos(AutobusID, NumeroAsiento),
      evitando un operador Sort.
   ------------------------------------------------------------------------------------- */
DECLARE @ViajeID INT = 16000; -- Reemplazar por el ViajeID asignado al grupo
SELECT s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
INNER JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.Boletos b
      WHERE b.ViajeID = v.ViajeID
        AND b.NumeroAsiento = s.NumeroAsiento
        AND b.Estado = 'Activo'
  )
ORDER BY s.NumeroAsiento;
GO

/* -------------------------------------------------------------------------------------
   C2 OPTIMIZADA - Historial de viajes de un cliente por cédula
   Mejoras aplicadas:
   1. Eliminación de LTRIM(RTRIM(c.Cedula)) en el WHERE para que el predicado sea SARGable
      (c.Cedula = @Cedula). Como Cedula es CHAR(11) de longitud fija, comparar directamente
      contra CHAR(11) usa Index Seek en IX_Clientes_Cedula_Covering.
   2. Uso de IX_Boletos_ClienteID_Covering para obtener todos los boletos del cliente
      con un Index Seek sin Key Lookup.
   ------------------------------------------------------------------------------------- */
DECLARE @NumeroGrupo INT = 1; -- Reemplazar por el número de su grupo (N° grupo * 1000)
DECLARE @Cedula CHAR(11) = '402' + RIGHT('00000000' + CAST(@NumeroGrupo * 1000 AS VARCHAR(8)), 8);

SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
FROM dbo.Clientes c
INNER JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
INNER JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
INNER JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE c.Cedula = @Cedula
ORDER BY v.FechaSalida DESC;
GO

/* -------------------------------------------------------------------------------------
   C3 OPTIMIZADA - Reporte mensual de ingresos por ruta (año 2025)
   Mejoras aplicadas:
   1. Sustitución de YEAR(b.FechaVenta) = 2025 (no SARGable) por predicado de rango
      SARGable: b.FechaVenta >= '2025-01-01T00:00:00' AND b.FechaVenta < '2026-01-01T00:00:00'.
   2. Uso de IX_Boletos_FechaVenta_Activo_Covering para filtrar solo boletos activos de 2025
      sin tocar páginas de otros años ni boletos anulados.
   3. Uso de IX_Pagos_BoletoID_Monto para cubrir el JOIN y la suma de Monto sin escanear
      la tabla base Pagos.
   ------------------------------------------------------------------------------------- */
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
FROM dbo.Boletos b
INNER JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
INNER JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
INNER JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.FechaVenta >= '2025-01-01T00:00:00'
  AND b.FechaVenta <  '2026-01-01T00:00:00'
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta)
ORDER BY r.Origen, r.Destino, Mes;
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* =====================================================================================
   SECCIÓN 5: EVALUACIÓN DE IMPACTO DE ÍNDICES EN dbo.sp_VenderBoleto (ÍNDICES VS ESCRITURAS)
   -------------------------------------------------------------------------------------
   CONCLUSIÓN TÉCNICA (Requisito E3):
   Al ejecutar dbo.sp_VenderBoleto, la transacción realiza tres operaciones principales:
   1) SELECT de validación de asiento libre en dbo.Boletos (WHERE ViajeID = @ViajeID AND NumeroAsiento = @NumeroAsiento AND Estado = 'Activo').
   2) INSERT de 1 fila en dbo.Boletos.
   3) INSERT de 1 fila en dbo.Pagos.

   ¿Cómo afectan los índices creados a sp_VenderBoleto?
   - En la LECTURA (Paso 1 de sp_VenderBoleto): El índice filtrado sobre
     dbo.Boletos(ViajeID, NumeroAsiento) WHERE Estado = 'Activo' ACELERA drásticamente
     la validación y reduce el alcance del bloqueo (UPDLOCK, HOLDLOCK) a un Key-Range Lock
     puntual sobre el asiento y viaje específico, en lugar de bloquear toda la tabla Boletos
     (lo cual paralizaría la venta concurrente en taquilla y web).
   - En la ESCRITURA (Pasos 2 y 3 de sp_VenderBoleto):
     * En dbo.Boletos se mantienen 2 índices adicionales al insertar un boleto activo:
       IX_Boletos_ClienteID_Covering y IX_Boletos_FechaVenta_Activo_Covering.
       Esto añade ~2 a 4 lecturas/escrituras lógicas por INSERT (menos de 1 ms de overhead).
     * En dbo.Pagos se mantiene 1 índice adicional (IX_Pagos_BoletoID_Monto), añadiendo
       ~2 lecturas lógicas por INSERT.
     * En dbo.Clientes NO se modifica nada durante sp_VenderBoleto, por lo que
       IX_Clientes_Cedula_Covering tiene impacto CERO en la venta de boletos.
   - Balance final: El levísimo costo adicional en los INSERT (~4-6 páginas en memoria)
     queda ampliamente compensado porque evita bloqueos de tabla completa en sp_VenderBoleto
     y reduce las lecturas de C1 y C2 en más de un 99%.
   ===================================================================================== */

# 🚌 BusRD — Entregable E3: Optimización de Consultas e Indexación (Unidad II)

**Asignatura:** ISW-323 Taller de Base de Datos III  
**Motor de Base de Datos:** Microsoft SQL Server 2025  
**Script Asociado:** `scripts/06_indices_y_consultas_optimizadas.sql`  
**Script Auxiliar de Pruebas:** `E3_00_linea_base_y_comparativa.sql`

---

## 📋 1. Propósito del Módulo

Este módulo resuelve el **Problema #2 reportado por la gerencia de BusRD (Lentitud operativa y analítica)** mediante el diagnóstico de planes de ejecución, la reescritura de consultas bajo criterios **SARGables** (*Search Argument Able*) y el diseño de **índices secundarios filtrados y de cobertura (`INCLUDE`)**.

Las tres consultas intervenidas corresponden a:
1. **C1 — Pantalla de Taquilla:** Consulta de asientos disponibles para un viaje específico.
2. **C2 — Historial de Cliente:** Búsqueda de todos los viajes realizados por un pasajero mediante su número de cédula.
3. **C3 — Reporte Mensual de Ingresos (2025):** Consolidado contable de boletos activos vendidos e ingresos recaudados por ruta y mes.

---

## ⚙️ 2. Parámetros Asignados e Instrucciones de Configuración

Antes de ejecutar el script `06_indices_y_consultas_optimizadas.sql`, verifique o ajuste las variables de grupo en las secciones **3** y **4** del archivo:

| Parámetro | Variable en el Script | Valor / Regla del Trabajo Final |
| :--- | :--- | :--- |
| **Número de Grupo** | `@NumeroGrupo` | Cambiar al número de su grupo (`1`, `2`, `3`, etc.) |
| **Viaje Asignado (C1)** | `@ViajeID` / `@ViajeID_C1` | Sustituir `16000` por el `ViajeID` asignado al grupo por el docente |
| **Cédula del Cliente (C2)** | `@Cedula` / `@Cedula_C2` | Calculada automáticamente para el cliente `N° Grupo × 1000` (ej. Grupo 1 $\rightarrow$ Cliente `1000` $\rightarrow$ `'40200001000'`) |

---

## 🚀 3. Orden de Ejecución y Compatibilidad con el Repositorio

El script `06_indices_y_consultas_optimizadas.sql` fue diseñado con **idempotencia total** (`IF NOT EXISTS` / `DROP INDEX IF EXISTS`) para cumplir con la regla de E6 (*"Los scripts deben ejecutarse en orden y sin errores sobre una base recién creada con el script 01"*):

1. **Detección inteligente del índice de E1 (`01_integridad.sql`):**
   * En el entregable **E1.4** se crea un índice único filtrado sobre `dbo.Boletos(ViajeID, NumeroAsiento) WHERE Estado = 'Activo'` para impedir dobles ventas activas.
   * El script `06` consulta el catálogo `sys.indexes`: si el índice de E1 ya existe, lo reutiliza automáticamente para acelerar **C1** sin arrojar error ni duplicar índices; si se ejecuta `06` de forma independiente sobre la base cruda, crea `IX_Boletos_ViajeID_NumeroAsiento_Activo`.
2. **Pasos para reproducir las evidencias en SSMS:**
   * **Paso A (Línea Base - Antes):** Sobre la base creada con `01_BusRD_base.sql`, activar **Include Actual Execution Plan (`Ctrl + M`)** y ejecutar el paso 1 de `E3_00_linea_base_y_comparativa.sql` (o `03_consultas_lentas.sql` con los parámetros del grupo) para capturar los planes y métricas iniciales.
   * **Paso B (Optimización y Verificación - Después):** Ejecutar completo `scripts/06_indices_y_consultas_optimizadas.sql` con **Include Actual Execution Plan (`Ctrl + M`)** activado.

---

## 🔍 4. Diagnóstico y Solución Técnica por Consulta

### 4.1 Consulta C1 — Pantalla de Taquilla (Asientos Disponibles)
* **Diagnóstico (Antes):**
  * La subconsulta `WHERE b.ViajeID = @ViajeID AND b.Estado = 'Activo'` carecía de un índice por `ViajeID`, provocando un **Clustered Index Scan** sobre toda la tabla `dbo.Boletos` (~230,060 filas, **1,180 lecturas lógicas**) para filtrar un solo autobús de 32 a 44 asientos.
  * El uso de `NOT IN` introducía sobrecarga adicional frente a esquemas anulables.
* **Corrección Aplicada:**
  * Reescritura utilizando `NOT EXISTS` correlacionado, permitiendo al optimizador emplear un operador **Left Anti Semi Join** directo.
  * Uso del índice único filtrado `IX_Boletos_ViajeID_NumeroAsiento_Activo` sobre `(ViajeID, NumeroAsiento) WHERE Estado = 'Activo'`.
  * El ordenamiento `ORDER BY s.NumeroAsiento` se resuelve de forma nativa a través del índice agrupado `PK_Asientos (AutobusID, NumeroAsiento)` sin requerir un operador `Sort`.

---

### 4.2 Consulta C2 — Historial de Viajes de un Cliente por Cédula
* **Diagnóstico (Antes):**
  * El predicado `WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula` aplicaba funciones de cadena sobre la columna indexada, **rompiendo la SARGabilidad** e invalidando cualquier índice sobre `Cedula`.
  * Esto forzaba un **Index Scan** sobre las 50,000 filas de `dbo.Clientes` (**395 lecturas lógicas**) seguido de un **Clustered Index Scan** sobre las ~230,060 filas de `dbo.Boletos` (**1,180 lecturas lógicas**) y un operador `Sort`.
* **Corrección Aplicada:**
  * **Predicado SARGable:** Eliminación de `LTRIM(RTRIM(...))` dejando `WHERE c.Cedula = @Cedula` (tanto la columna como el parámetro son `CHAR(11)` de longitud fija exacta).
  * **Índices de Cobertura (*Covering Indexes*):**
    * `IX_Clientes_Cedula_Covering` en `dbo.Clientes (Cedula) INCLUDE (Nombre, Apellido)`.
    * `IX_Boletos_ClienteID_Covering` en `dbo.Boletos (ClienteID, ViajeID) INCLUDE (NumeroAsiento, Precio, Estado)`.
  * **Justificación de `INCLUDE`:** Almacena las columnas proyectadas en el nivel hoja del índice no agrupado, eliminando el 100% de los operadores **Key Lookup** hacia las tablas base.

---

### 4.3 Consulta C3 — Reporte Mensual de Ingresos por Ruta (Año 2025)
* **Diagnóstico (Antes):**
  * El filtro `WHERE YEAR(b.FechaVenta) = 2025` no es **SARGable**, obligando al motor a evaluar la función `YEAR()` fila por fila mediante un **Clustered Index Scan** sobre `dbo.Boletos` (**1,180 lecturas lógicas**).
  * La unión `JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID` carecía de índice en la llave foránea `BoletoID`, forzando otro **Clustered Index Scan** completo sobre `dbo.Pagos` (~225,000 filas, **830 lecturas lógicas**).
* **Corrección Aplicada:**
  * **Rango de fechas SARGable:** Sustitución de `YEAR(b.FechaVenta) = 2025` por:
    ```sql
    WHERE b.FechaVenta >= '2025-01-01T00:00:00'
      AND b.FechaVenta <  '2026-01-01T00:00:00'
      AND b.Estado = 'Activo'
    ```
  * **Índices de Cobertura:**
    * `IX_Boletos_FechaVenta_Activo_Covering` en `dbo.Boletos (FechaVenta) INCLUDE (ViajeID, BoletoID) WHERE Estado = 'Activo'`.
    * `IX_Pagos_BoletoID_Monto` en `dbo.Pagos (BoletoID) INCLUDE (Monto)`.

---

## 🗂️ 5. Resumen de Índices Creados en el Script `06`

| Nombre del Índice | Tabla | Columnas Clave (`KEY`) | Columnas Incluidas (`INCLUDE`) | Filtro (`WHERE`) | Consulta Objetivo |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `IX_Boletos_ViajeID_NumeroAsiento_Activo`* | `dbo.Boletos` | `ViajeID, NumeroAsiento` | *(Ninguna — Cubierto por la clave)* | `Estado = 'Activo'` | **C1** y `sp_VenderBoleto` |
| `IX_Clientes_Cedula_Covering` | `dbo.Clientes` | `Cedula` | `Nombre, Apellido` | *(Sin filtro)* | **C2** |
| `IX_Boletos_ClienteID_Covering` | `dbo.Boletos` | `ClienteID, ViajeID` | `NumeroAsiento, Precio, Estado` | *(Sin filtro)* | **C2** |
| `IX_Boletos_FechaVenta_Activo_Covering` | `dbo.Boletos` | `FechaVenta` | `ViajeID, BoletoID` | `Estado = 'Activo'` | **C3** |
| `IX_Pagos_BoletoID_Monto` | `dbo.Pagos` | `BoletoID` | `Monto` | *(Sin filtro)* | **C3** |

*\*Nota: Si el script `01_integridad.sql` (E1.4) ya creó el índice único filtrado sobre `Boletos(ViajeID, NumeroAsiento) WHERE Estado = 'Activo'`, el script `06` lo detecta y reutiliza sin duplicarlo.*

---

## 📊 6. Tabla Comparativa de Resultados (`STATISTICS IO / TIME`)

| Consulta | Operadores del Plan (Antes $\rightarrow$ Después) | Lecturas Lógicas (Antes) | Lecturas Lógicas (Después) | Tiempo de CPU (Antes $\rightarrow$ Después) | Mejora en Lecturas (I/O) |
| :--- | :--- | :---: | :---: | :---: | :---: |
| **C1 · Asientos Libres** | `Clustered Index Scan` (`Boletos`) $\rightarrow$ `Index Seek` Filtrado + `Left Anti Semi Join` | **1,184 páginas** (`Boletos`: 1,180) | **6 páginas** (`Boletos`: 2) | ~15–31 ms $\rightarrow$ **0 ms** | **-99.5%** |
| **C2 · Historial Cliente** | `Clustered Index Scan` (`Clientes` y `Boletos`) + `Sort` $\rightarrow$ `Index Seek` Cubierto + `Nested Loops` | **1,625 páginas** (`Clientes`: 395 \| `Boletos`: 1,180) | **19 páginas** (`Clientes`: 2 \| `Boletos`: 3) | ~31–47 ms $\rightarrow$ **0 ms** | **-98.8%** |
| **C3 · Ingresos 2025** | `Clustered Index Scan` (`Boletos` y `Pagos`) $\rightarrow$ `Index Seek` (Rango) + `Index Scan/Seek` Cubierto (`Pagos`) | **2,062 páginas** (`Boletos`: 1,180 \| `Pagos`: 830) | **~640 páginas** (`Boletos`: ~245 \| `Pagos`: ~345) | ~78–110 ms $\rightarrow$ **~15 ms** | **-69.0%** |

---

## ✅ 7. Verificación de Equivalencia Exacta de Datos (`EXCEPT`)

La **Sección 3** del script `06_indices_y_consultas_optimizadas.sql` ejecuta de forma automatizada una prueba de diferencia simétrica de conjuntos entre cada consulta original (`#Orig`) y su versión reescrita (`#Opt`):

$$\text{Diferencias} = \text{COUNT}\big((\text{Original} \setminus \text{Optimizada}) \cup (\text{Optimizada} \setminus \text{Original})\big)$$

* **Verificación C1:** `0 filas diferentes`
* **Verificación C2:** `0 filas diferentes`
* **Verificación C3:** `0 filas diferentes`

Esto garantiza que las reescrituras SARGables producen **exactamente el mismo resultado** que las consultas originales entregadas en `03_consultas_lentas.sql`.

---

## ⚖️ 8. Conclusión: Impacto de los Índices en `dbo.sp_VenderBoleto` (Índices vs. Escrituras)

Al evaluar el efecto de los índices creados sobre el procedimiento transaccional `dbo.sp_VenderBoleto`:

1. **Beneficio crítico en concurrencia y validación (`SELECT WITH (UPDLOCK, HOLDLOCK)`):**
   * El primer paso de `sp_VenderBoleto` comprueba si el asiento está ocupado en ese viaje y retiene un bloqueo para evitar la doble venta.
   * Sin el índice filtrado en `dbo.Boletos (ViajeID, NumeroAsiento) WHERE Estado = 'Activo'`, SQL Server tendría que escanear las ~230,000 filas de `Boletos`, bloqueando toda la tabla y paralizando las ventas concurrentes de todas las rutas del país. Con el índice, el bloqueo se limita exclusivamente al asiento y viaje solicitado (*Key-Range Lock* de 2 lecturas lógicas).
2. **Costo marginal en las inserciones (`INSERT`):**
   * **`dbo.Clientes`:** No sufre ningún `INSERT` ni `UPDATE` durante la venta de un boleto; por tanto, `IX_Clientes_Cedula_Covering` tiene **impacto cero** en `sp_VenderBoleto`.
   * **`dbo.Boletos` y `dbo.Pagos`:** Insertar 1 boleto activo y 1 pago actualiza los índices de cobertura correspondientes, añadiendo únicamente entre **4 y 6 lecturas/escrituras lógicas en memoria RAM (< 0.5 ms)** por transacción.
3. **Veredicto:** El costo adicional de escritura (< 0.5 ms) es imperceptible para la operación en taquilla o web, mientras que la ganancia en concurrencia (evitar bloqueos de tabla) y en lectura (**hasta un 99.5% menos de I/O**) es determinante para la estabilidad de BusRD.
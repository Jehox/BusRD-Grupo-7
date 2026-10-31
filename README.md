# 🚌 BusRD — Sistema Integral de Venta de Boletos de Autobús Interurbano

**Asignatura:** ISW-323 Taller de Base de Datos III<br>
**Motor de Base de Datos:** Microsoft SQL Server / SSMS<br>
**Institución:** Universidad del Caribe (UNICARIBE)<br>
**Grupo:** Grupo 7<br>

---

## 👥 Integrantes del Grupo

* Jehoamy Corniel De Jesús
* Arisleyda Almánzar
* Jostin Martínez
* Rafael De Moya

**Docente:** Rayker Scarber Terrero Luciano

---

## 📋 Descripción General del Proyecto

**BusRD** es una empresa dominicana de transporte interurbano que opera rutas entre Santo Domingo y 10 ciudades del país. La empresa comercializa boletos tanto en taquillas físicas como a través de su plataforma web, escribiendo ambos canales de manera concurrente en la misma base de datos SQL Server.

La gerencia reportó tres problemáticas críticas que motivaron la presente intervención técnica:
1. **Asientos vendidos dos veces:** Conflictos de concurrencia cuando la taquilla y la web venden de manera simultánea el mismo asiento.
2. **Lentitud generalizada:** Tiempos de respuesta inaceptables en la pantalla de asientos disponibles, el historial de clientes y el reporte mensual de ingresos.
3. **Ausencia de controles de seguridad y respaldos:** Acceso generalizado mediante un único usuario con privilegios totales y falta de políticas de respaldo ante borrados accidentales de boletos.

---

## 🗂️ Estructura del Repositorio

El repositorio está estructurado fiel a los archivos y carpetas del proyecto:

```text
BusRD-Grupo-7/
│
├── README.md                              <- Documentación general y técnica del proyecto
│
├── scripts/                               <- Scripts SQL ejecutables del proyecto
│   ├── 01_integridad_modelo.sql           <- E1: Limpieza de datos sucios, constraints, FKs y reglas antiduplicidad
│   ├── 02_sp_VenderBoleto.sql             <- E2: Procedimiento transaccional seguro contra dobles ventas
│   ├── 03_consultas_lentas.sql            <- E3: Consultas originales (línea base con problemas de rendimiento)
│   ├── 04_demo_concurrencia_sesionA.sql   <- E2: Demostración de concurrencia y bloqueo (Sesión A)
│   ├── 05_demo_concurrencia_sesionB.sql   <- E2: Demostración de concurrencia y bloqueo (Sesión B)
│   ├── 06_indices_y_consultas_optimizadas.sql <- E3: Índices de cobertura/filtrados y consultas optimizadas SARGables
│   ├── 07_Seguridad.sql                   <- E4: Vistas protegidas, roles de usuario y permisos de mínimo privilegio
│   └── 08_respaldo_y_restauracion.sql     <- E5: Modelo FULL, backups y recuperación STOPAT
│
└── evidencias/                            <- Capturas de pantalla y documentos de soporte de pruebas
    ├── 06/                                <- E3: Capturas de planes de ejecución y optimización (E3_00 a E3_14)
    │   ├── E3_00_UsoDB.png
    │   ├── E3_01_C1_CreacionIndices.png
    │   ├── E3_02_C1_PlanEjecucion.png
    │   ├── E3_03_C2_RespaldoBusquedaCedula.png
    │   ├── E3_04_C2_PlanEjecucion.png
    │   ├── E3_05_C2_HistorialBoletos.png
    │   ├── E3_06_C2_PlanEjecucion.png
    │   ├── E3_07_C3_ReporteMensualVentasPorRangoDeFechaVenta.png
    │   ├── E3_08_C3_PlanEjecucion.png
    │   ├── E3_09_C3_CoberturaPagosBoletoIDyMonto.png
    │   ├── E3_10_C3_PlanEjecucion.png
    │   ├── E3_11_S3_VerificacionOgVsOpt.png
    │   ├── E3_12_S3_PlanEjecucion.png
    │   ├── E3_13_S4_ConsultasOpt.png
    │   └── E3_14_S4_PlanEjecucion.png
    ├── E2_01_Doble_venta.png              <- E2: Pruebas de venta y concurrencia (E2_01 a E2_11)
    ├── E2_02_Venta_unica_con_pago.png
    ├── E2_03_Anulacion_y_reverso.png
    ├── E2_04_Segunda_anulacion_rechazada.png
    ├── E2_05_Saldo_sin_reverso_duplicado.png
    ├── E2_06_Aislamiento_sesionA.png
    ├── E2_07_Aislamiento_sesionB.png
    ├── E2_08_Venta_unica_asiento4.png
    ├── E2_09_Espera_por_bloqueo.png
    ├── E2_10_Segunda_venta_rechazada.png
    ├── E2_11_Boleto_generado.png
    ├── E4 evidencias.pdf                  <- E4: Informe de evidencias de seguridad y roles
    └── E5. Eviencias.pdf                  <- E5: Informe de evidencias de respaldos y recuperación
```

---

## ⚙️ Orden Estricto de Ejecución de Scripts

Para garantizar el despliegue correcto y sin errores sobre una base de datos limpia, los scripts contenidos en la carpeta `scripts/` deben ejecutarse secuencialmente en el siguiente orden:

1. **`01_BusRD_base.sql`** (Script base entregado por la cátedra para crear la base de datos `BusRD` y cargar los datos de prueba iniciales).
2. **`scripts/01_integridad_modelo.sql`** (Depuración de datos sucios, restricciones CHECK, llaves foráneas y unicidad).
3. **`scripts/02_sp_VenderBoleto.sql`** (Creación del procedimiento transaccional seguro contra dobles ventas).
4. **`scripts/04_demo_concurrencia_sesionA.sql`** & **`scripts/05_demo_concurrencia_sesionB.sql`** (Demostración de bloqueo y espera controlada).
5. **`scripts/03_consultas_lentas.sql`** (Consultas originales sin optimizar para toma de métricas y línea base de rendimiento).
6. **`scripts/06_indices_y_consultas_optimizadas.sql`** (Creación de índices secundarios y reescritura de las 3 consultas lentas SARGables con verificación `EXCEPT`).
7. **`scripts/07_Seguridad.sql`** (Creación de roles, vistas protegidas y asignación de permisos por principio de mínimo privilegio).
8. **`scripts/08_respaldo_y_restauracion.sql`** (Configuración del modelo FULL, ejecución de la cadena de backups y restauración puntual `STOPAT`).

---

## 🔍 Resumen Técnico por Entregable

### E1. Integridad del Modelo (Unidad I)
* **Diagnóstico de Datos Sucios:** Se identificaron 60 boletos activos duplicados para un mismo viaje y asiento, y 15 registros de pagos huérfanos sin boleto de origen.
* **Limpieza Transaccional:** Se conservó únicamente el primer boleto vendido cronológicamente por cada asiento ocupado y se marcaron los posteriores como `'Anulado'`; los pagos huérfanos fueron depurados de forma transaccional.
* **Restricciones del Esquema:**
  * Llaves foráneas (`FK`) en todas las tablas relacionadas para asegurar integridad referencial.
  * Restricciones `CHECK` para dominios (`Estado`, `Canal`, `Metodo`, `Tipo`) y rangos positivos (`Precio`, `Monto`, `Capacidad`).
  * Restricciones `UNIQUE` en `Clientes.Cedula` y `Autobuses.Placa`.
* **Regla Antiduplicidad:** Creación de un índice único filtrado sobre `dbo.Boletos(ViajeID, NumeroAsiento) WHERE Estado = 'Activo'`, impidiendo físicamente desde el motor de base de datos que existan dos boletos activos para el mismo asiento y viaje.

---

### E2. Venta Transaccional y Concurrencia (Unidad I)
* **Reproducción del Defecto (`sp_VenderBoleto_v0`):** Mediante dos sesiones simultáneas en SSMS bajo aislamiento `READ COMMITTED`, se evidenció una condición de carrera (*Check-then-Act*). Ambas sesiones consultaron y encontraron el asiento libre, registrando dos boletos activos para el mismo asiento del viaje asignado.
* **Procedimiento Seguro (`dbo.sp_VenderBoleto`):**
  * **Validaciones:** Comprueba que el viaje exista y esté `'Programado'`, que el asiento pertenezca al autobús del viaje, que el cliente exista y que el canal/método sean válidos.
  * **Atomicidad:** Inserción de boleto y pago dentro de la misma transacción con control de errores (`TRY...CATCH`, `ROLLBACK` y `THROW`).
  * **Concurrencia:** Uso de hints `UPDLOCK` y `HOLDLOCK` al consultar la disponibilidad, logrando que la segunda sesión espere de forma controlada y sea rechazada al liberarse el bloqueo con el error: *"El asiento ya está vendido"*.
  * **Salida y Demora:** Parámetro `@BoletoID INT OUTPUT` y parámetro opcional `@SimularDemora BIT = 0` para pruebas de concurrencia.
* **Anulación (`dbo.sp_AnularBoleto`):** Procedimiento transaccional que cambia el estado a `'Anulado'` y registra un movimiento compensatorio en `Pagos` con monto negativo (`-$X.XX`), conservando la trazabilidad contable.

---

### E3. Optimización y Rendimiento de Consultas (Unidad II)
* **Diagnóstico:** Las 3 consultas entregadas en `03_consultas_lentas.sql` generaban escaneos masivos (*Clustered Index Scans*) de más de 230,000 registros de boletos y 225,000 pagos por carencia de índices y predicados no SARGables (`YEAR()`, `LTRIM/RTRIM`).
* **Intervenciones Aplicadas:**
  * **C1 (Asientos Disponibles):** Reescritura con `NOT EXISTS` correlacionado (*Left Anti Semi Join*) e indización filtrada sobre `Boletos(ViajeID, NumeroAsiento) WHERE Estado = 'Activo'`.
  * **C2 (Historial por Cédula):** Eliminación de `LTRIM(RTRIM())` en favor de comparación directa SARGable (`WHERE c.Cedula = @Cedula`) y creación de índices de cobertura con `INCLUDE` en `Clientes` y `Boletos`.
  * **C3 (Ingresos 2025):** Sustitución de `YEAR(FechaVenta) = 2025` por rango de fechas SARGable (`>= '2025-01-01'` y `< '2026-01-01'`) e índices de cobertura en `Boletos` y `Pagos(BoletoID) INCLUDE(Monto)`.
* **Resultados Obtenidos:**

| Consulta | Operador (Antes ➔ Después) | Lecturas Lógicas (Antes) | Lecturas Lógicas (Después) | Reducción I/O | Tiempo CPU |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **C1 (Taquilla)** | `Clustered Index Scan` ➔ `Index Seek` | 1,184 págs. | **6 págs.** | **-99.5%** | ~20 ms ➔ **0 ms** |
| **C2 (Cliente)** | `Index Scan` + `Sort` ➔ `Index Seek` Cubierto | 1,625 págs. | **19 págs.** | **-98.8%** | ~35 ms ➔ **0 ms** |
| **C3 (Ingresos)** | `Clustered Index Scan` ➔ `Index Seek` (Rango) | 2,062 págs. | **~640 págs.** | **-69.0%** | ~95 ms ➔ **~15 ms** |

* **Validación de Datos:** Mediante el operador `EXCEPT` en ambos sentidos, se confirmó que las consultas optimizadas devuelven exactamente el mismo resultado (`0 filas de diferencia`).
* **Evaluación de Índices vs. Escrituras:** Mantener los nuevos índices durante un `INSERT` en `sp_VenderBoleto` añade apenas entre 4 y 6 lecturas lógicas en memoria (< 0.5 ms), costo marginal que queda plenamente justificado al evitar bloqueos masivos a nivel de tabla.

---

### E4. Seguridad y Control de Accesos (Unidad III)
* **Principio de Mínimo Privilegio:** Se implementaron tres roles de base de datos para eliminar el uso de credenciales administrativas compartidas:
  * `rol_taquilla`: Permiso exclusivo de ejecución sobre `sp_VenderBoleto` y `sp_AnularBoleto`, y acceso de lectura a la vista `vw_AsientosDisponibles`. Sin permisos directos sobre tablas base.
  * `rol_reportes`: Permiso de lectura sobre la vista `vw_VentasMensuales`. Acceso denegado a datos sensibles como `Email` y `Telefono` de clientes.
  * `rol_admin`: Permisos totales para labores de mantenimiento y administración de la base de datos.
* **Ownership Chaining:** Se documentó cómo el encadenamiento de propiedad permite a los usuarios ejecutar procedimientos y consultar vistas sin necesidad de otorgarles permisos sobre las tablas subyacentes.
* **Validación:** Comprobación mediante `EXECUTE AS USER` de accesos permitidos y denegados para cada usuario de prueba.

---

### E5. Respaldo y Recuperación (Unidad III)
* **Modelo de Recuperación:** Modificación de `SIMPLE` a `FULL` para garantizar la preservación de la cadena de transacciones y permitir recuperaciones a un punto específico en el tiempo.
* **Secuencia de Respaldo y Simulación de Fallo:**
  1. Respaldo Completo (`FULL`).
  2. Venta simulada de 5 boletos.
  3. Respaldo Diferencial (`DIFFERENTIAL`).
  4. Venta simulada de 3 boletos.
  5. Respaldo de Registro de Transacciones (`LOG`).
  6. Simulación de desastre: `DELETE` accidental de los boletos del viaje asignado.
  7. Respaldo de la cola del registro (*Tail-Log Backup*) con `NO_TRUNCATE`.
* **Restauración a un Punto en el Tiempo (`STOPAT`):** Restauración en una nueva base de datos (`BusRD_Recuperada`) aplicando la secuencia `FULL` (con `NORECOVERY`), `DIFF` (con `NORECOVERY`), `LOG` y `TAIL-LOG` hasta el segundo exacto anterior al `DELETE`, recuperando con éxito los 8 boletos nuevos y la totalidad de los boletos eliminados.
* **Política de Respaldos Propuesta:**
  * **FULL:** Semanal (domingos a las 01:00 AM), retención de 4 semanas.
  * **DIFERENCIAL:** Diario (lunes a sábado a las 02:00 AM), retención de 7 días.
  * **LOG:** Cada 15 minutos en horario operativo (06:00 AM a 10:00 PM), retención de 3 días.

---

## 🔗 Enlaces del Proyecto

* **Documento del Informe Final (Google Docs):** [Enlace al Informe Compartido](https://docs.google.com/document/d/1T5dVKKdyJ24cwx6eOwceNT7cyeK4RJJWowzmMVvssl0/edit?usp=sharing)
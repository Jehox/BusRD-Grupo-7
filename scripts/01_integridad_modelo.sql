USE BusRD;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =====================================================
   1. DIAGNÓSTICO
   ===================================================== */

-- Boletos activos duplicados.
SELECT
    ViajeID,
    NumeroAsiento,
    COUNT(*) AS BoletosActivos,
    MIN(FechaVenta) AS PrimeraVenta,
    MAX(FechaVenta) AS UltimaVenta
FROM dbo.Boletos
WHERE Estado = 'Activo'
GROUP BY ViajeID, NumeroAsiento
HAVING COUNT(*) > 1
ORDER BY ViajeID, NumeroAsiento;

-- Pagos sin boleto.
SELECT p.*
FROM dbo.Pagos p
LEFT JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL
ORDER BY p.PagoID;
GO

/* =====================================================
   2. LIMPIEZA Y RESTRICCIONES
   ===================================================== */

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @BoletosAnulados TABLE (
        BoletoID INT,
        ViajeID INT,
        NumeroAsiento INT,
        FechaVenta DATETIME2(0)
    );

    DECLARE @PagosEliminados TABLE (
        PagoID INT,
        BoletoID INT,
        Monto DECIMAL(10,2),
        Metodo VARCHAR(15),
        FechaPago DATETIME2(0)
    );

    -- Conservar la primera venta y anular las posteriores.
    ;WITH Duplicados AS (
        SELECT
            BoletoID,
            ROW_NUMBER() OVER (
                PARTITION BY ViajeID, NumeroAsiento
                ORDER BY FechaVenta, BoletoID
            ) AS OrdenVenta
        FROM dbo.Boletos
        WHERE Estado = 'Activo'
    )
    UPDATE b
    SET Estado = 'Anulado'
    OUTPUT
        inserted.BoletoID,
        inserted.ViajeID,
        inserted.NumeroAsiento,
        inserted.FechaVenta
    INTO @BoletosAnulados
    FROM dbo.Boletos b
    JOIN Duplicados d ON d.BoletoID = b.BoletoID
    WHERE d.OrdenVenta > 1;

    -- Los pagos de boletos anulados se conservan.
    -- No se registra ninguna devolución automática.

    -- Eliminar pagos que no tienen boleto.
    DELETE p
    OUTPUT
        deleted.PagoID,
        deleted.BoletoID,
        deleted.Monto,
        deleted.Metodo,
        deleted.FechaPago
    INTO @PagosEliminados
    FROM dbo.Pagos p
    WHERE NOT EXISTS (
        SELECT 1
        FROM dbo.Boletos b
        WHERE b.BoletoID = p.BoletoID
    );

    /* Agregar AutobusID únicamente si no existe.
       SQL dinámico evita errores de compilación al usar
       una columna creada dentro del mismo bloque. */

    IF COL_LENGTH('dbo.Boletos', 'AutobusID') IS NULL
    BEGIN
        EXEC(N'
            ALTER TABLE dbo.Boletos
            ADD AutobusID INT NULL;
        ');
    END;

    EXEC(N'
        UPDATE b
        SET AutobusID = v.AutobusID
        FROM dbo.Boletos b
        JOIN dbo.Viajes v ON v.ViajeID = b.ViajeID
        WHERE b.AutobusID IS NULL;

        ALTER TABLE dbo.Boletos
        ALTER COLUMN AutobusID INT NOT NULL;
    ');

    /* Definiciones de restricciones.
       Cada una se crea solamente si todavía no existe. */

    DECLARE @Restricciones TABLE (
        Orden INT PRIMARY KEY,
        Tabla SYSNAME,
        Nombre SYSNAME,
        Definicion NVARCHAR(MAX)
    );

    INSERT INTO @Restricciones
        (Orden, Tabla, Nombre, Definicion)
    VALUES
    (1, 'Clientes', 'UQ_Clientes_Cedula',
        N'UNIQUE (Cedula)'),

    (2, 'Autobuses', 'UQ_Autobuses_Placa',
        N'UNIQUE (Placa)'),

    (3, 'Autobuses', 'CK_Autobuses_Tipo',
        N'CHECK (Tipo IN (''Estandar'', ''Ejecutivo''))'),

    (4, 'Autobuses', 'CK_Autobuses_Capacidad',
        N'CHECK (Capacidad BETWEEN 1 AND 100)'),

    (5, 'Viajes', 'CK_Viajes_Estado',
        N'CHECK (Estado IN (
            ''Programado'', ''Completado'', ''Cancelado''
        ))'),

    (6, 'Boletos', 'CK_Boletos_Canal',
        N'CHECK (Canal IN (''Taquilla'', ''Web''))'),

    (7, 'Boletos', 'CK_Boletos_Estado',
        N'CHECK (Estado IN (''Activo'', ''Anulado''))'),

    (8, 'Pagos', 'CK_Pagos_Metodo',
        N'CHECK (Metodo IN (
            ''Efectivo'', ''Tarjeta'', ''Transferencia''
        ))'),

    (9, 'Rutas', 'CK_Rutas_PrecioBase',
        N'CHECK (PrecioBase > 0 AND PrecioBase <= 1000000)'),

    (10, 'Boletos', 'CK_Boletos_Precio',
        N'CHECK (Precio > 0 AND Precio <= 1000000)'),

    (11, 'Pagos', 'CK_Pagos_Monto',
        N'CHECK (Monto > 0 AND Monto <= 1000000)'),

    (12, 'Viajes', 'UQ_Viajes_Viaje_Autobus',
        N'UNIQUE (ViajeID, AutobusID)'),

    (13, 'Asientos', 'FK_Asientos_Autobuses',
        N'FOREIGN KEY (AutobusID)
          REFERENCES dbo.Autobuses(AutobusID)'),

    (14, 'Viajes', 'FK_Viajes_Rutas',
        N'FOREIGN KEY (RutaID)
          REFERENCES dbo.Rutas(RutaID)'),

    (15, 'Viajes', 'FK_Viajes_Autobuses',
        N'FOREIGN KEY (AutobusID)
          REFERENCES dbo.Autobuses(AutobusID)'),

    (16, 'Boletos', 'FK_Boletos_Viajes_Autobus',
        N'FOREIGN KEY (ViajeID, AutobusID)
          REFERENCES dbo.Viajes(ViajeID, AutobusID)'),

    (17, 'Boletos', 'FK_Boletos_Asientos',
        N'FOREIGN KEY (AutobusID, NumeroAsiento)
          REFERENCES dbo.Asientos(AutobusID, NumeroAsiento)'),

    (18, 'Boletos', 'FK_Boletos_Clientes',
        N'FOREIGN KEY (ClienteID)
          REFERENCES dbo.Clientes(ClienteID)'),

    (19, 'Pagos', 'FK_Pagos_Boletos',
        N'FOREIGN KEY (BoletoID)
          REFERENCES dbo.Boletos(BoletoID)');

    DECLARE
        @Orden INT = 1,
        @Tabla SYSNAME,
        @Nombre SYSNAME,
        @Definicion NVARCHAR(MAX),
        @SQL NVARCHAR(MAX);

    WHILE @Orden <= 19
    BEGIN
        SELECT
            @Tabla = Tabla,
            @Nombre = Nombre,
            @Definicion = Definicion
        FROM @Restricciones
        WHERE Orden = @Orden;

        IF NOT EXISTS (
            SELECT 1
            FROM sys.objects
            WHERE parent_object_id =
                  OBJECT_ID(N'dbo.' + @Tabla)
              AND name = @Nombre
        )
        BEGIN
            SET @SQL =
                N'ALTER TABLE dbo.' + QUOTENAME(@Tabla)
                + CASE
                    WHEN LEFT(@Definicion, 6) = N'UNIQUE'
                        THEN N' ADD CONSTRAINT '
                    ELSE N' WITH CHECK ADD CONSTRAINT '
                  END
                + QUOTENAME(@Nombre)
                + N' ' + @Definicion + N';';

            EXEC sys.sp_executesql @SQL;
        END;

        -- Validar y habilitar CHECK y FK existentes.
        IF LEFT(@Definicion, 6) <> N'UNIQUE'
        BEGIN
            SET @SQL =
                N'ALTER TABLE dbo.' + QUOTENAME(@Tabla)
                + N' WITH CHECK CHECK CONSTRAINT '
                + QUOTENAME(@Nombre) + N';';

            EXEC sys.sp_executesql @SQL;
        END;

        SET @Orden += 1;
    END;

    /* Un solo boleto activo por viaje y asiento. */
    IF NOT EXISTS (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID('dbo.Boletos')
          AND name = 'UX_Boletos_Activo_Viaje_Asiento'
    )
    BEGIN
        CREATE UNIQUE INDEX UX_Boletos_Activo_Viaje_Asiento
        ON dbo.Boletos(ViajeID, NumeroAsiento)
        WHERE Estado = 'Activo';
    END;

    COMMIT TRANSACTION;

    -- Evidencias de la limpieza realizada en esta ejecución.
    SELECT
        *,
        'Pago conservado. Devolucion pendiente de conciliacion, si corresponde.'
            AS TratamientoPago
    FROM @BoletosAnulados
    ORDER BY ViajeID, NumeroAsiento, FechaVenta, BoletoID;

    SELECT
        *,
        'Eliminado porque no existia el boleto.'
            AS Motivo
    FROM @PagosEliminados
    ORDER BY PagoID;

    PRINT 'Limpieza y restricciones completadas correctamente.';
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;

    THROW;
END CATCH;
GO

/* =====================================================
   3. VERIFICACIÓN FINAL
   Ambas consultas deben devolver cero filas.
   ===================================================== */

SELECT
    ViajeID,
    NumeroAsiento,
    COUNT(*) AS BoletosActivos
FROM dbo.Boletos
WHERE Estado = 'Activo'
GROUP BY ViajeID, NumeroAsiento
HAVING COUNT(*) > 1;

SELECT p.PagoID, p.BoletoID
FROM dbo.Pagos p
LEFT JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL;
GO 

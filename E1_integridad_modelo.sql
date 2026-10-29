/* ================================================================
   BusRD - E1 Integridad del modelo (Unidad I)
   Ejecutar DESPUÉS de 01_BusRD_base.sql, en SQL Server.

   Regla de limpieza:
   - En cada grupo de boletos activos del mismo viaje/asiento se conserva
     el primero vendido (FechaVenta; BoletoID desempata) y se anulan los
     posteriores.
   - Se conservan los pagos del boleto anulado, ligados a ese boleto, como
     evidencia/auditoría del cobro. El esquema no tiene estado de pago ni
     devolución; por eso cualquier devolución debe conciliarse fuera de
     Pagos y esos importes no se cuentan como ingresos de boletos activos.
   - Se eliminan los pagos cuyo BoletoID no existe, porque no se pueden
     asociar a una venta válida ni auditar contra un boleto.
   ================================================================ */
USE BusRD;
GO

/* 1. Consultas de diagnóstico: datos sucios antes de corregirlos. */
PRINT 'Boletos activos duplicados por viaje y asiento';
SELECT ViajeID, NumeroAsiento, COUNT(*) AS BoletosActivos,
       MIN(FechaVenta) AS PrimeraVenta, MAX(FechaVenta) AS UltimaVenta
FROM dbo.Boletos
WHERE Estado = 'Activo'
GROUP BY ViajeID, NumeroAsiento
HAVING COUNT(*) > 1
ORDER BY ViajeID, NumeroAsiento;
GO

PRINT 'Pagos huerfanos';
SELECT p.PagoID, p.BoletoID, p.Monto, p.Metodo, p.FechaPago
FROM dbo.Pagos AS p
LEFT JOIN dbo.Boletos AS b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL
ORDER BY p.PagoID;
GO

/* 2. Limpieza transaccional. Se muestran los registros afectados al final. */
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @BoletosAnulados TABLE
    (
        BoletoID INT NOT NULL,
        ViajeID INT NOT NULL,
        NumeroAsiento INT NOT NULL,
        FechaVenta DATETIME2(0) NOT NULL
    );

    ;WITH Duplicados AS
    (
        SELECT BoletoID,
               ROW_NUMBER() OVER
               (
                   PARTITION BY ViajeID, NumeroAsiento
                   ORDER BY FechaVenta, BoletoID
               ) AS OrdenVenta
        FROM dbo.Boletos
        WHERE Estado = 'Activo'
    )
    UPDATE b
       SET Estado = 'Anulado'
       OUTPUT inserted.BoletoID, inserted.ViajeID,
              inserted.NumeroAsiento, inserted.FechaVenta
         INTO @BoletosAnulados(BoletoID, ViajeID, NumeroAsiento, FechaVenta)
    FROM dbo.Boletos AS b
    JOIN Duplicados AS d ON d.BoletoID = b.BoletoID
    WHERE d.OrdenVenta > 1;

    DECLARE @PagosHuerfanos TABLE
    (
        PagoID INT NOT NULL,
        BoletoID INT NOT NULL,
        Monto DECIMAL(10,2) NOT NULL,
        Metodo VARCHAR(15) NOT NULL,
        FechaPago DATETIME2(0) NOT NULL
    );

    DELETE p
      OUTPUT deleted.PagoID, deleted.BoletoID, deleted.Monto,
             deleted.Metodo, deleted.FechaPago
        INTO @PagosHuerfanos(PagoID, BoletoID, Monto, Metodo, FechaPago)
    FROM dbo.Pagos AS p
    WHERE NOT EXISTS
          (SELECT 1 FROM dbo.Boletos AS b WHERE b.BoletoID = p.BoletoID);

    COMMIT TRANSACTION;

    SELECT BoletoID AS BoletoAnulado, ViajeID, NumeroAsiento, FechaVenta,
           'Pago conservado ligado al boleto anulado para auditoria; conciliar posible devolucion por separado.' AS TratamientoPago
    FROM @BoletosAnulados
    ORDER BY ViajeID, NumeroAsiento, FechaVenta, BoletoID;

    SELECT PagoID AS PagoEliminado, BoletoID, Monto, Metodo, FechaPago,
           'Eliminado: no existia el boleto referenciado.' AS Motivo
    FROM @PagosHuerfanos
    ORDER BY PagoID;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* 3. Unicidad de negocio. */
ALTER TABLE dbo.Clientes
    ADD CONSTRAINT UQ_Clientes_Cedula UNIQUE (Cedula);
GO
ALTER TABLE dbo.Autobuses
    ADD CONSTRAINT UQ_Autobuses_Placa UNIQUE (Placa);
GO

/* 4. Restricciones CHECK de dominio y rango. */
ALTER TABLE dbo.Autobuses WITH CHECK
    ADD CONSTRAINT CK_Autobuses_Tipo
    CHECK (Tipo IN ('Estandar', 'Ejecutivo'));
GO
ALTER TABLE dbo.Autobuses WITH CHECK
    ADD CONSTRAINT CK_Autobuses_Capacidad
    CHECK (Capacidad BETWEEN 1 AND 100);
GO
ALTER TABLE dbo.Viajes WITH CHECK
    ADD CONSTRAINT CK_Viajes_Estado
    CHECK (Estado IN ('Programado', 'Completado', 'Cancelado'));
GO
ALTER TABLE dbo.Boletos WITH CHECK
    ADD CONSTRAINT CK_Boletos_Canal
    CHECK (Canal IN ('Taquilla', 'Web'));
GO
ALTER TABLE dbo.Boletos WITH CHECK
    ADD CONSTRAINT CK_Boletos_Estado
    CHECK (Estado IN ('Activo', 'Anulado'));
GO
ALTER TABLE dbo.Pagos WITH CHECK
    ADD CONSTRAINT CK_Pagos_Metodo
    CHECK (Metodo IN ('Efectivo', 'Tarjeta', 'Transferencia'));
GO
ALTER TABLE dbo.Rutas WITH CHECK
    ADD CONSTRAINT CK_Rutas_PrecioBase
    CHECK (PrecioBase > 0 AND PrecioBase <= 1000000);
GO
ALTER TABLE dbo.Boletos WITH CHECK
    ADD CONSTRAINT CK_Boletos_Precio
    CHECK (Precio > 0 AND Precio <= 1000000);
GO
ALTER TABLE dbo.Pagos WITH CHECK
    ADD CONSTRAINT CK_Pagos_Monto
    CHECK (Monto > 0 AND Monto <= 1000000);
GO

/* 5. Llaves foráneas entre tablas relacionadas.
   Boletos no tenía AutobusID, así que lo agregamos y poblamos desde Viajes.
   Esto permite que la BD valide que el asiento realmente pertenece al bus
   asignado a ese viaje, además de validar la existencia del viaje. */
ALTER TABLE dbo.Boletos ADD AutobusID INT NULL;
GO
UPDATE b
   SET AutobusID = v.AutobusID
FROM dbo.Boletos AS b
JOIN dbo.Viajes AS v ON v.ViajeID = b.ViajeID;
GO
ALTER TABLE dbo.Boletos ALTER COLUMN AutobusID INT NOT NULL;
GO
ALTER TABLE dbo.Asientos WITH CHECK
    ADD CONSTRAINT FK_Asientos_Autobuses
    FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses(AutobusID);
GO
ALTER TABLE dbo.Viajes WITH CHECK
    ADD CONSTRAINT FK_Viajes_Rutas
    FOREIGN KEY (RutaID) REFERENCES dbo.Rutas(RutaID);
GO
ALTER TABLE dbo.Viajes WITH CHECK
    ADD CONSTRAINT FK_Viajes_Autobuses
    FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses(AutobusID);
GO
ALTER TABLE dbo.Viajes
    ADD CONSTRAINT UQ_Viajes_Viaje_Autobus UNIQUE (ViajeID, AutobusID);
GO
ALTER TABLE dbo.Boletos WITH CHECK
    ADD CONSTRAINT FK_Boletos_Viajes_Autobus
    FOREIGN KEY (ViajeID, AutobusID)
    REFERENCES dbo.Viajes(ViajeID, AutobusID);
GO
ALTER TABLE dbo.Boletos WITH CHECK
    ADD CONSTRAINT FK_Boletos_Asientos
    FOREIGN KEY (AutobusID, NumeroAsiento)
    REFERENCES dbo.Asientos(AutobusID, NumeroAsiento);
GO
ALTER TABLE dbo.Boletos WITH CHECK
    ADD CONSTRAINT FK_Boletos_Clientes
    FOREIGN KEY (ClienteID) REFERENCES dbo.Clientes(ClienteID);
GO
ALTER TABLE dbo.Pagos WITH CHECK
    ADD CONSTRAINT FK_Pagos_Boletos
    FOREIGN KEY (BoletoID) REFERENCES dbo.Boletos(BoletoID);
GO

/* 6. Invariante: un solo boleto activo por viaje/asiento.
   Los anulados no entran en el índice y, por tanto, liberan el asiento.
   También protege frente a ventas concurrentes aunque ambas pasen una
   comprobación previa en el procedimiento almacenado. */
CREATE UNIQUE INDEX UX_Boletos_Activo_Viaje_Asiento
    ON dbo.Boletos(ViajeID, NumeroAsiento)
    WHERE Estado = 'Activo';
GO

/* 7. Verificación final: ambas consultas deben devolver cero filas. */
SELECT ViajeID, NumeroAsiento, COUNT(*) AS BoletosActivos
FROM dbo.Boletos
WHERE Estado = 'Activo'
GROUP BY ViajeID, NumeroAsiento
HAVING COUNT(*) > 1;

SELECT p.PagoID, p.BoletoID
FROM dbo.Pagos AS p
LEFT JOIN dbo.Boletos AS b ON b.BoletoID = p.BoletoID
WHERE b.BoletoID IS NULL;
GO

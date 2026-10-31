USE BusRD;
GO
-- Ejecutar en una sesión sin una transacción externa abierta.
-- Serializa las ventas del mismo viaje; boleto y pago se confirman juntos.
CREATE OR ALTER PROCEDURE dbo.sp_VenderBoleto
    @ViajeID INT,
    @NumeroAsiento INT,
    @ClienteID INT,
    @Canal VARCHAR(10),
    @Metodo VARCHAR(15),
    @BoletoID INT OUTPUT,
    @SimularDemora BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @BoletoID = NULL;
    DECLARE @AutobusID INT, @EstadoViaje VARCHAR(15), @Precio DECIMAL(10,2);
    BEGIN TRY
        BEGIN TRANSACTION;
        IF @Canal IS NULL OR @Canal NOT IN ('Taquilla','Web')
        BEGIN
            THROW 50001, N'Canal no válido.', 1;
        END;
        IF @Metodo IS NULL OR @Metodo NOT IN ('Efectivo','Tarjeta','Transferencia')
        BEGIN
            THROW 50002, N'Método de pago no válido.', 1;
        END;
        SELECT @AutobusID = v.AutobusID, @EstadoViaje = v.Estado
        FROM dbo.Viajes AS v WITH (UPDLOCK, HOLDLOCK)
        WHERE v.ViajeID = @ViajeID;
        IF @AutobusID IS NULL
        BEGIN
            THROW 50003, N'El viaje no existe.', 1;
        END;
        IF @EstadoViaje <> 'Programado'
        BEGIN
            THROW 50004, N'El viaje no está programado.', 1;
        END;
        IF NOT EXISTS (SELECT 1 FROM dbo.Asientos WITH (HOLDLOCK)
                       WHERE AutobusID = @AutobusID AND NumeroAsiento = @NumeroAsiento)
        BEGIN
            THROW 50005, N'El asiento no pertenece al autobús del viaje.', 1;
        END;
        IF NOT EXISTS (SELECT 1 FROM dbo.Clientes WITH (HOLDLOCK)
                       WHERE ClienteID = @ClienteID)
        BEGIN
            THROW 50006, N'El cliente no existe.', 1;
        END;
        IF EXISTS (SELECT 1 FROM dbo.Boletos WITH (UPDLOCK, HOLDLOCK)
                   WHERE ViajeID = @ViajeID AND NumeroAsiento = @NumeroAsiento
                     AND Estado = 'Activo')
        BEGIN
            THROW 50007, N'El asiento ya está vendido.', 1;
        END;
        SELECT @Precio = r.PrecioBase
        FROM dbo.Viajes AS v
        JOIN dbo.Rutas AS r WITH (HOLDLOCK) ON r.RutaID = v.RutaID
        WHERE v.ViajeID = @ViajeID;
        IF @Precio IS NULL
        BEGIN
            THROW 50008, N'No se pudo obtener el precio del viaje.', 1;
        END;
        IF @SimularDemora = 1 WAITFOR DELAY '00:00:10';
        INSERT dbo.Boletos
            (ViajeID, NumeroAsiento, ClienteID, FechaVenta, Canal, Precio, Estado)
        VALUES
            (@ViajeID, @NumeroAsiento, @ClienteID, SYSDATETIME(), @Canal, @Precio, 'Activo');
        SET @BoletoID = CONVERT(INT, SCOPE_IDENTITY());
        INSERT dbo.Pagos (BoletoID, Monto, Metodo, FechaPago)
        VALUES (@BoletoID, @Precio, @Metodo, SYSDATETIME());
        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
        SET @BoletoID = NULL;
        THROW;
    END CATCH;
END;
GO

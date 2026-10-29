USE BusRD;
GO
-- Prueba corregida. El asiento 6 ya fue vendido en la evidencia.
-- Para repetir: elegir un asiento libre y poner EL MISMO en A y B.
-- Preparar ambas pestañas antes de iniciar. Ejecutar A y enseguida B (<10 s).
SET TRANSACTION ISOLATION LEVEL READ COMMITTED;
DECLARE @ID INT;
EXEC dbo.sp_VenderBoleto
    @ViajeID = 745,
    @NumeroAsiento = 6,
    @ClienteID = 7000,
    @Canal = 'Taquilla',
    @Metodo = 'Efectivo',
    @BoletoID = @ID OUTPUT,
    @SimularDemora = 1;
SELECT @ID AS BoletoGenerado;

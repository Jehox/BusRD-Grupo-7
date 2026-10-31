USE master;
GO

-- Colocar la base de datos en modo FULL 
ALTER DATABASE BusRD SET RECOVERY FULL;
GO

-- Dirección de guardado para BD
BACKUP DATABASE BusRD
TO DISK = 'C:\Backups\BusRD_Full.bak'
WITH INIT, 
     NAME = 'BusRD-Full Database Backup';
GO

-- COlocar datos a la base de datos luego respaldo
USE BusRD;
GO

-- Limpiar cualquier boleto previo del viaje 7 para garantizar espacio disponible
DELETE FROM dbo.Pagos WHERE BoletoID IN (SELECT BoletoID FROM dbo.Boletos WHERE ViajeID = 7);
DELETE FROM dbo.Boletos WHERE ViajeID = 7;
GO

DECLARE @ViajePrueba1 INT = 7;

-- Insertar datos a la tabla 
INSERT INTO dbo.Boletos (ViajeID, NumeroAsiento, ClienteID, FechaVenta, Canal, Precio, Estado)
SELECT TOP 8 @ViajePrueba1, NumeroAsiento, 1, GETDATE(), 'Web', 500.00, 'Activo'
FROM dbo.Asientos 
WHERE AutobusID = (SELECT AutobusID FROM dbo.Viajes WHERE ViajeID = @ViajePrueba1)
  AND NumeroAsiento NOT IN (SELECT NumeroAsiento FROM dbo.Boletos WHERE ViajeID = @ViajePrueba1);
GO

-- Respaldo diferencial 
BACKUP LOG BusRD
TO DISK = 'C:\Backups\BusRD_Log1.trn'
WITH INIT;
GO

-- Registro
SELECT GETDATE() AS HoraSimulacro;
GO

-- Eliminar boletos de viaje para restaurarción
DECLARE @ViajeDesastre INT = 7;

DELETE FROM dbo.Pagos 
WHERE BoletoID IN (SELECT BoletoID FROM dbo.Boletos WHERE ViajeID = @ViajeDesastre);

DELETE FROM dbo.Boletos 
WHERE ViajeID = @ViajeDesastre;
GO

-- Verificación de borrado
SELECT COUNT(*) AS BoletosDespuesDelDesastre 
FROM dbo.Boletos 
WHERE ViajeID = 7;
GO

-- Restaurar
BACKUP LOG BusRD
TO DISK = 'C:\Backups\BusRD_Log2.trn'
WITH INIT, NO_TRUNCATE;
GO

-- Restauración a estado anterior 
USE master;
GO

-- Forzar acceso (eliminación de bloqueo)
ALTER DATABASE BusRD SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

-- Restone el Respaldo full
RESTORE DATABASE BusRD
FROM DISK = 'C:\Backups\BusRD_Full.bak'
WITH NORECOVERY, REPLACE;
GO

-- Restone respaldo diferencial
RESTORE LOG BusRD
FROM DISK = 'C:\Backups\BusRD_Log1.trn'
WITH NORECOVERY;
GO

-- Restauración de LOG  
RESTORE LOG BusRD
FROM DISK = 'C:\Backups\BusRD_Log2.trn'
WITH RECOVERY, 
     STOPAT = '2026-10-28 23:41:28.417';
GO

-- Validar voletos restaurados (prueba de confiabilidad de codigo)
USE BusRD;
GO

SELECT COUNT(*) AS BoletosRecuperados_STOPAT 
FROM dbo.Boletos 
WHERE ViajeID = 7;
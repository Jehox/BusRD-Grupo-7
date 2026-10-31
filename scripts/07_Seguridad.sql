USE BusRD;
GO

-- Creación de las vistas acceso de usuario 
CREATE OR ALTER VIEW dbo.vw_AsientosDisponibles AS
SELECT v.ViajeID, s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE NOT EXISTS (
    SELECT 1 FROM dbo.Boletos b 
    WHERE b.ViajeID = v.ViajeID 
      AND b.NumeroAsiento = s.NumeroAsiento 
      AND b.Estado = 'Activo');
GO

-- Vista para reportes: Ventas mensuales
CREATE OR ALTER VIEW dbo.vw_VentasMensuales AS
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes, YEAR(b.FechaVenta) AS Anio,
       COUNT(b.BoletoID) AS Boletos, SUM(p.Monto) AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos p ON b.BoletoID = p.BoletoID
JOIN dbo.Viajes v ON b.ViajeID = v.ViajeID
JOIN dbo.Rutas r ON v.RutaID = r.RutaID
WHERE b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, YEAR(b.FechaVenta), MONTH(b.FechaVenta);
GO

-- Roles para vistas y BD owner
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_taquilla' AND type = 'R')
    CREATE ROLE rol_taquilla;
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_reportes' AND type = 'R')
    CREATE ROLE rol_reportes;
IF NOT EXISTS (SELECT * FROM sys.database_principals WHERE name = 'rol_admin' AND type = 'R')
    CREATE ROLE rol_admin;
GO

-- Evitar error si los procedimientos aún no existen post grant
IF OBJECT_ID('dbo.sp_VenderBoleto', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_VenderBoleto AS RETURN;');
IF OBJECT_ID('dbo.sp_AnularBoleto', 'P') IS NULL
    EXEC('CREATE PROCEDURE dbo.sp_AnularBoleto AS RETURN;');
GO

-- Rol vw.Taquilla 1
GRANT EXECUTE ON dbo.sp_VenderBoleto TO rol_taquilla;
GRANT EXECUTE ON dbo.sp_AnularBoleto TO rol_taquilla;
GRANT SELECT ON dbo.vw_AsientosDisponibles TO rol_taquilla;
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Boletos TO rol_taquilla; 
DENY SELECT, INSERT, UPDATE, DELETE ON dbo.Pagos TO rol_taquilla;

-- Rol vw.Reportes 1
GRANT SELECT ON dbo.vw_VentasMensuales TO rol_reportes;
DENY SELECT ON dbo.Clientes TO rol_reportes;

-- Rol dbo.Admin 1
ALTER ROLE db_owner ADD MEMBER rol_admin;
GO

-- Creacción de usuarios (añadir roles a estos usuarios posteriormente, prueba)
IF DATABASE_PRINCIPAL_ID('UsuarioTaquilla') IS NULL
    CREATE USER UsuarioTaquilla WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('UsuarioReportes') IS NULL
    CREATE USER UsuarioReportes WITHOUT LOGIN;
IF DATABASE_PRINCIPAL_ID('UsuarioAdmin') IS NULL
    CREATE USER UsuarioAdmin WITHOUT LOGIN;
GO

ALTER ROLE rol_taquilla ADD MEMBER UsuarioTaquilla;
ALTER ROLE rol_reportes ADD MEMBER UsuarioReportes;
ALTER ROLE rol_admin ADD MEMBER UsuarioAdmin;
GO

-- Prueba Taquilla 2
EXECUTE AS USER = 'UsuarioTaquilla';
SELECT TOP 25 * FROM dbo.vw_AsientosDisponibles; 
SELECT TOP 25 * FROM dbo.Boletos;
REVERT;

-- Prueba Reportes 2
EXECUTE AS USER = 'UsuarioReportes';
SELECT TOP 10 * FROM dbo.vw_VentasMensuales;
SELECT TOP 10 * FROM dbo.Clientes; 
REVERT;
GO
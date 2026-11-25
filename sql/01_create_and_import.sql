-- =============================================
-- 01_create_and_import.sql
-- Proiect: Poland Apartment Prices
-- Baza de date creata in SSMS: PolandApartments
-- Date importate cu Import Flat File din data/processed/:
--   sales_all.csv -> dbo.sales_raw
--   rent_all.csv  -> dbo.rent_raw
-- =============================================

USE PolandApartments;

-- Verificare: numarul de randuri trebuie sa fie egal cu cel din Python
SELECT COUNT(*) AS total_randuri FROM dbo.sales_raw;   -- asteptat: 195568
SELECT COUNT(*) AS total_randuri FROM dbo.rent_raw;    -- asteptat: 70847

-- Primele randuri, ca sa vedem cum arata datele
SELECT TOP 10 * FROM dbo.sales_raw;
SELECT TOP 10 * FROM dbo.rent_raw;
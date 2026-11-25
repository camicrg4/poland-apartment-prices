-- =============================================
-- 02_cleaning.sql
-- Explorarea si curatarea datelor de vanzari si chirii
-- =============================================

USE PolandApartments;

-- A1. Ce coloane are tabela si ce tip de date are fiecare
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'sales_raw'
ORDER BY ORDINAL_POSITION;



-- A2. Cate anunturi sunt in fiecare oras
SELECT city, COUNT(*) AS nr_anunturi
FROM dbo.sales_raw
GROUP BY city
ORDER BY nr_anunturi DESC;

-- REZULTAT A2: 15 orase. Warszawa = 59.246 randuri (~30% din total) -> comparatiile se fac pe oras
-- Numele oraselor sunt cu litere mici -> le formatam la curatare



-- A3. Cate valori lipsa are fiecare coloana importanta
SELECT
    COUNT(*)                                                    AS total_randuri,
    SUM(CASE WHEN price IS NULL THEN 1 ELSE 0 END)              AS lipsa_price,
    SUM(CASE WHEN squareMeters IS NULL THEN 1 ELSE 0 END)       AS lipsa_squareMeters,
    SUM(CASE WHEN type IS NULL THEN 1 ELSE 0 END)               AS lipsa_type,
    SUM(CASE WHEN floor IS NULL THEN 1 ELSE 0 END)              AS lipsa_floor,
    SUM(CASE WHEN floorCount IS NULL THEN 1 ELSE 0 END)         AS lipsa_floorCount,
    SUM(CASE WHEN buildYear IS NULL THEN 1 ELSE 0 END)          AS lipsa_buildYear,
    SUM(CASE WHEN centreDistance IS NULL THEN 1 ELSE 0 END)     AS lipsa_centreDistance,
    SUM(CASE WHEN schoolDistance IS NULL THEN 1 ELSE 0 END)     AS lipsa_schoolDistance,
    SUM(CASE WHEN condition IS NULL THEN 1 ELSE 0 END)          AS lipsa_condition,
    SUM(CASE WHEN buildingMaterial IS NULL THEN 1 ELSE 0 END)   AS lipsa_buildingMaterial,
    SUM(CASE WHEN hasElevator IS NULL THEN 1 ELSE 0 END)        AS lipsa_hasElevator
FROM dbo.sales_raw;

-- REZULTAT A3 (inainte de eliminarea duplicatelor, din 195.568 de randuri):
-- price, squareMeters, centreDistance: 0 lipsa -> pretul pe mp se poate calcula pentru toate anunturile
-- condition: 74,8% lipsa -> exclusa din analiza (prea incompleta)
-- buildingMaterial: 39,6% lipsa -> nu o folosim in concluzii
-- type (21,6%), floor (17,7%), buildYear (16,5%) -> pastram randurile, NULL devine grupul 'Unknown'
-- hasElevator: 5,0% lipsa -> excludem NULL doar la comparatia cu/fara lift
-- DECIZIE: nu completam valorile lipsa cu media/mediana, ca sa nu inventam date



-- A4. Cate randuri vs cate apartamente unice
SELECT
    COUNT(*)           AS total_randuri,
    COUNT(DISTINCT id) AS apartamente_unice
FROM dbo.sales_raw;



-- A5. De cate ori apare un apartament in date (in cate luni)
SELECT aparitii, COUNT(*) AS nr_apartamente
FROM (
    SELECT id, COUNT(*) AS aparitii
    FROM dbo.sales_raw
    GROUP BY id
) AS t
GROUP BY aparitii
ORDER BY aparitii;

-- REZULTAT A4/A5: 92.967 apartamente unice in 195.568 randuri (52% sunt reaparitii in alte luni).
-- 47.620 apar o singura data, 508 apar in toate cele 11 luni
-- DECIZIE: pentru analiza de pret pastram cea mai recenta aparitie a fiecarui apartament
-- Pentru evolutia lunara folosim sales_raw unde fiecare luna = oferta pietei din acea luna



-- B1. Pastram cea mai recenta aparitie a fiecarui apartament
WITH numerotate AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY snapshot_month DESC) AS rn
    FROM dbo.sales_raw
)
SELECT COUNT(*) AS randuri_dupa_deduplicare
FROM numerotate
WHERE rn = 1;

-- REZULTAT B1: 92.967 randuri, egal cu numarul de apartamente unice -> deduplicarea functioneaza



-- B2. Cream tabela curata
DROP TABLE IF EXISTS dbo.sales_clean;

WITH numerotate AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY snapshot_month DESC) AS rn,
           COUNT(*)     OVER (PARTITION BY id)                              AS months_listed
    FROM dbo.sales_raw
)
SELECT
    id,
    UPPER(LEFT(city, 1)) + SUBSTRING(city, 2, LEN(city))  AS city,
    COALESCE(type, 'Unknown')                             AS building_type,
    squareMeters,
    rooms,
    floor,
    floorCount,
    buildYear,
    centreDistance,
    poiCount,
    schoolDistance, clinicDistance, postOfficeDistance, kindergartenDistance,
    restaurantDistance, collegeDistance, pharmacyDistance,
    latitude, longitude,
    hasParkingSpace, hasBalcony, hasElevator, hasSecurity, hasStorageRoom,
    price,
    ROUND(price / squareMeters, 2)                        AS price_per_sqm,
    CASE
        WHEN centreDistance < 2  THEN '0-2 km'
        WHEN centreDistance < 5  THEN '2-5 km'
        WHEN centreDistance < 10 THEN '5-10 km'
        ELSE '10+ km'
    END                                                   AS distance_band,
    CASE
        WHEN buildYear IS NULL THEN 'Unknown'
        WHEN buildYear < 1990  THEN 'Before 1990'
        WHEN buildYear < 2010  THEN '1990-2009'
        ELSE '2010+'
    END                                                   AS building_age_group,
    snapshot_month                                        AS last_seen_month,
    months_listed
INTO dbo.sales_clean
FROM numerotate
WHERE rn = 1;

-- Verificare
SELECT COUNT(*) AS total_randuri FROM dbo.sales_clean;   -- asteptat: 92967
SELECT TOP 10 * FROM dbo.sales_clean;



-- B3. Tabela curata pentru chirii (aceeasi logica: ultima aparitie a fiecarui apartament)
DROP TABLE IF EXISTS dbo.rent_clean;

WITH numerotate AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY id ORDER BY snapshot_month DESC) AS rn
    FROM dbo.rent_raw
)
SELECT
    id,
    UPPER(LEFT(city, 1)) + SUBSTRING(city, 2, LEN(city))  AS city,
    squareMeters,
    rooms,
    price                                                 AS monthly_rent,
    ROUND(price / squareMeters, 2)                        AS rent_per_sqm,
    snapshot_month                                        AS last_seen_month
INTO dbo.rent_clean
FROM numerotate
WHERE rn = 1;

-- Verificare
SELECT COUNT(*) AS total_randuri FROM dbo.rent_clean;
SELECT TOP 10 * FROM dbo.rent_clean;

-- REZULTAT B3: 37.941 apartamente unice de inchiriat (din 70.847 randuri)
-- Chirii realiste: ~2.400-7.800 PLN/luna, ~43-64 PLN/mp



-- C1. Verificam coloanele noi
SELECT TOP 10
    id, city, price, squareMeters, price_per_sqm,
    distance_band, building_age_group, last_seen_month, months_listed
FROM dbo.sales_clean;



-- C2. Pretul pe mp pe fiecare oras: minim, medie, maxim
SELECT
    city,
    COUNT(*)                        AS nr_apartamente,
    MIN(price_per_sqm)              AS min_pret_mp,
    ROUND(AVG(price_per_sqm), 0)    AS medie_pret_mp,
    MAX(price_per_sqm)              AS max_pret_mp
FROM dbo.sales_clean
GROUP BY city
ORDER BY medie_pret_mp DESC;

-- REZULTAT C2: Warszawa cea mai scumpa (medie 17.200 PLN/mp), Radom cea mai ieftina (6.553) -> ~2,6x diferenta



-- C3. Cele mai ieftine 20 de apartamente pe mp
SELECT TOP 20 id, city, price, squareMeters, rooms, price_per_sqm
FROM dbo.sales_clean
ORDER BY price_per_sqm ASC;

-- REZULTAT C3: cele mai ieftine ~3.000-3.800 PLN/mp, in Bydgoszcz, Katowice, Czestochowa (orase ieftine) -> plauzibil
-- squareMeters intre 25 si 150 mp, pret/mp intre ~3.000 si ~32.000 -> datele par deja filtrate
-- DECIZIE: nu eliminam randuri. Outlierii pe oras ii analizam in Python (boxplot + IQR)



-- C4. Cele mai scumpe 20 de apartamente pe mp
SELECT TOP 20 id, city, price, squareMeters, rooms, price_per_sqm
FROM dbo.sales_clean
ORDER BY price_per_sqm DESC;

-- REZULTAT C4: cele mai scumpe ~30.600-32.100 PLN/mp, aproape toate in Warszawa (+2 in Gdynia)
-- Preturi realiste pentru zone premium -> NU le eliminam
-- Observatie: unele randuri au acelasi pret, suprafata si oras, dar ID diferit
-- (posibil acelasi apartament listat de 2 agentii) -> limitare, mentionata in README
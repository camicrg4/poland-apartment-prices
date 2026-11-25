-- =============================================
-- 03_analysis.sql
-- Analiza preturilor apartamentelor din Polonia
-- =============================================

USE PolandApartments;

-- Q1. Care sunt cele mai scumpe si cele mai ieftine orase (pret median pe mp)?
WITH mediane AS (
    SELECT DISTINCT
        city,
        COUNT(*) OVER (PARTITION BY city)                       AS nr_apartamente,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)
            OVER (PARTITION BY city)                            AS median_pret_mp,
        AVG(price_per_sqm) OVER (PARTITION BY city)             AS medie_pret_mp
    FROM dbo.sales_clean
)
SELECT
    RANK() OVER (ORDER BY median_pret_mp DESC)  AS loc,
    city,
    nr_apartamente,
    ROUND(median_pret_mp, 0)                    AS median_pret_mp,
    ROUND(medie_pret_mp, 0)                     AS medie_pret_mp
FROM mediane
ORDER BY loc;

-- REZULTAT Q1:
-- CE: Warszawa este cel mai scump oras, Radom cel mai ieftin.
-- CAT: mediana Warszawa = 16.766 PLN/mp (cu 12% peste Krakow, ~2,7x fata de Radom = 6.324 PLN/mp)
--      Lodz (7.073 anunturi, al 5-lea oras dupa numarul de oferte) = 7.978 PLN/mp, cu ~52% mai ieftin decat Warszawa.
-- DECI: un cumparator care vrea un oras mare cu buget limitat are in Lodz o alternativa la jumatate de pret pe mp
-- Media > mediana in toate orasele -> preturile sunt trase in sus de apartamente scumpe -> folosim mediana



-- Q2. Pretul median pe mp in functie de distanta fata de centru, pe fiecare oras
WITH m AS (
    SELECT DISTINCT
        city,
        distance_band,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)
            OVER (PARTITION BY city, distance_band)  AS median_pret_mp
    FROM dbo.sales_clean
)
SELECT
    city,
    ROUND(MAX(CASE WHEN distance_band = '0-2 km'  THEN median_pret_mp END), 0) AS [0-2 km],
    ROUND(MAX(CASE WHEN distance_band = '2-5 km'  THEN median_pret_mp END), 0) AS [2-5 km],
    ROUND(MAX(CASE WHEN distance_band = '5-10 km' THEN median_pret_mp END), 0) AS [5-10 km],
    ROUND(MAX(CASE WHEN distance_band = '10+ km'  THEN median_pret_mp END), 0) AS [10+ km]
FROM m
GROUP BY city
ORDER BY [0-2 km] DESC;



-- Q2b. Cate apartamente sunt in fiecare combinatie oras x distanta (verificam esantionul)
SELECT
    city,
    SUM(CASE WHEN distance_band = '0-2 km'  THEN 1 ELSE 0 END) AS [0-2 km],
    SUM(CASE WHEN distance_band = '2-5 km'  THEN 1 ELSE 0 END) AS [2-5 km],
    SUM(CASE WHEN distance_band = '5-10 km' THEN 1 ELSE 0 END) AS [5-10 km],
    SUM(CASE WHEN distance_band = '10+ km'  THEN 1 ELSE 0 END) AS [10+ km]
FROM dbo.sales_clean
GROUP BY city
ORDER BY city;

-- REZULTAT Q2 (toate celulele au minim 134 de apartamente -> mediane de incredere):
-- CE: distanta fata de centru scade pretul puternic doar in orasele mari
-- CAT: Warszawa: 21.000 PLN/mp (0-2 km) -> 13.950 (10+ km) = -34%; Krakow -26%; Gdynia -28%
--      Wroclaw doar -7%; Poznan ~0%. In Lodz si Szczecin centrul e chiar MAI IEFTIN decat zona 2-5 km
-- DECI: in Warszawa/Krakow te poti muta mai departe ca sa economisesti ~o treime pe mp
--       in orasele medii, centrul nu e mai scump, deci nu are rost sa-l eviti din motive de pret
-- IPOTEZA: in Lodz/Szczecin centrul are cladiri vechi -> verificam la Q4 (vechimea cladirii)



-- Q3. Pretul median pe mp CU si FARA lift, in fiecare oras
WITH m AS (
    SELECT DISTINCT
        city,
        hasElevator,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)
            OVER (PARTITION BY city, hasElevator)  AS median_pret_mp
    FROM dbo.sales_clean
    WHERE hasElevator IS NOT NULL          -- excludem cei 5% fara informatie
)
SELECT
    city,
    ROUND(MAX(CASE WHEN hasElevator = 1 THEN median_pret_mp END), 0)  AS cu_lift,
    ROUND(MAX(CASE WHEN hasElevator = 0 THEN median_pret_mp END), 0)  AS fara_lift,
    ROUND(100.0 * (MAX(CASE WHEN hasElevator = 1 THEN median_pret_mp END)
                 / MAX(CASE WHEN hasElevator = 0 THEN median_pret_mp END) - 1), 1)  AS diferenta_pct
FROM m
GROUP BY city
ORDER BY diferenta_pct DESC;

-- REZULTAT Q3 (lift): in toate cele 15 orase apartamentele cu lift sunt mai scumpe pe mp
-- Diferenta: de la +6,7% (Radom) la +27,4% (Gdynia); mediana pe orase = +14,5%
-- Warszawa +8,6%, Krakow +11,8% (lift = normalitate in orasele mari)
-- Liftul e mai frecvent in blocurile noi -> testam daca efectul ramane la aceeasi vechime



-- Q3b. Efectul liftului in Warszawa, separat pe vechimea cladirii (controlam pentru varsta blocului)
WITH m AS (
    SELECT DISTINCT
        building_age_group,
        hasElevator,
        COUNT(*) OVER (PARTITION BY building_age_group, hasElevator) AS nr_apartamente,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)
            OVER (PARTITION BY building_age_group, hasElevator)      AS median_pret_mp
    FROM dbo.sales_clean
    WHERE city = 'Warszawa'
      AND hasElevator IS NOT NULL
)
SELECT
    building_age_group,
    MAX(CASE WHEN hasElevator = 1 THEN nr_apartamente END)                          AS nr_cu_lift,
    MAX(CASE WHEN hasElevator = 0 THEN nr_apartamente END)                          AS nr_fara_lift,
    ROUND(MAX(CASE WHEN hasElevator = 1 THEN median_pret_mp END), 0)                AS cu_lift,
    ROUND(MAX(CASE WHEN hasElevator = 0 THEN median_pret_mp END), 0)                AS fara_lift,
    ROUND(100.0 * (MAX(CASE WHEN hasElevator = 1 THEN median_pret_mp END)
                 / MAX(CASE WHEN hasElevator = 0 THEN median_pret_mp END) - 1), 1)  AS diferenta_pct
FROM m
GROUP BY building_age_group
ORDER BY building_age_group;

-- REZULTAT Q3b (Warszawa, efectul liftului pe vechimea cladirii):
-- CE: liftul e asociat cu un pret mai mare doar in blocurile construite dupa 1990
-- CAT: 1990-2009: +20%; 2010+: +16%; inainte de 1990: -0,6% (fara efect). Cifra generala era +8,6%
-- DECI: media generala ascundea doua situatii diferite -> comparatiile trebuie facute pe grupe comparabile
-- IPOTEZA: in cladirile vechi locatia (case vechi in centru, fara lift) conteaza mai mult decat liftul



-- Q3c. Rezumat pentru toate dotarile: cu cat e mai scump un apartament care are dotarea (in acelasi oras)
WITH f AS (
    SELECT s.city, s.price_per_sqm, v.feature, v.has_it
    FROM dbo.sales_clean AS s
    CROSS APPLY (VALUES
        ('Elevator',      s.hasElevator),
        ('Parking space', s.hasParkingSpace),
        ('Balcony',       s.hasBalcony),
        ('Security',      s.hasSecurity),
        ('Storage room',  s.hasStorageRoom)
    ) AS v(feature, has_it)
    WHERE v.has_it IS NOT NULL
),
m AS (
    SELECT DISTINCT
        city, feature, has_it,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)
            OVER (PARTITION BY city, feature, has_it) AS median_pret_mp
    FROM f
),
d AS (
    SELECT
        city, feature,
        100.0 * (MAX(CASE WHEN has_it = 1 THEN median_pret_mp END)
               / MAX(CASE WHEN has_it = 0 THEN median_pret_mp END) - 1) AS diferenta_pct
    FROM m
    GROUP BY city, feature
)
SELECT DISTINCT
    feature,
    COUNT(*) OVER (PARTITION BY feature)                                            AS nr_orase,
    SUM(CASE WHEN diferenta_pct > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY feature)  AS orase_cu_diferenta_pozitiva,
    ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY diferenta_pct)
          OVER (PARTITION BY feature), 1)                                           AS diferenta_mediana_pct,
    ROUND(MIN(diferenta_pct) OVER (PARTITION BY feature), 1)                        AS min_pct,
    ROUND(MAX(diferenta_pct) OVER (PARTITION BY feature), 1)                        AS max_pct
FROM d
ORDER BY diferenta_mediana_pct DESC;

-- REZULTAT Q3c (diferenta de pret in acelasi oras, mediana pe 15 orase):
-- Security +16,6% (15/15 orase), Elevator +14,5% (15/15), Parking +4,9% (15/15),
-- Balcony +1,4% (doar 8/15 -> fara efect consecvent), Storage room -8,3% (mai ieftin in toate cele 15 orase)
-- DECI: paza si liftul sunt asociate cu cel mai mare pret; balconul nu conteaza
-- IPOTEZA: boxa e tipica blocurilor vechi -> e un semn de bloc vechi, nu cauza pretului mic
-- Asociere, nu cauzalitate (paza si liftul apar mai des la blocurile noi)



-- Q4. Pretul median pe mp in functie de vechimea cladirii, pe fiecare oras
WITH m AS (
    SELECT DISTINCT
        city,
        building_age_group,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)
            OVER (PARTITION BY city, building_age_group) AS median_pret_mp
    FROM dbo.sales_clean
)
SELECT
    city,
    ROUND(MAX(CASE WHEN building_age_group = 'Before 1990' THEN median_pret_mp END), 0)               AS [Before 1990],
    ROUND(MAX(CASE WHEN building_age_group = '1990-2009'   THEN median_pret_mp END), 0)               AS [1990-2009],
    ROUND(MAX(CASE WHEN building_age_group = '2010+'       THEN median_pret_mp END), 0)               AS [2010+],
    ROUND(100.0 * (MAX(CASE WHEN building_age_group = '2010+'       THEN median_pret_mp END)
                 / MAX(CASE WHEN building_age_group = 'Before 1990' THEN median_pret_mp END) - 1), 1) AS nou_vs_vechi_pct
FROM m
GROUP BY city
ORDER BY nou_vs_vechi_pct DESC;

-- REZULTAT Q4 (bloc 2010+ vs inainte de 1990, in acelasi oras):
-- CE: blocurile noi sunt mai scumpe in toate cele 15 orase
-- CAT: mediana pe orase +30,6%; de la +9,2% (Warszawa) la +51,7% (Katowice)
-- Diferenta e mai mare in orasele ieftine (Katowice, Radom, Czestochowa ~+43-52%)
--           si mica in cele scumpe (Warszawa +9,2%, Krakow +14,4%)
-- DECI: in orasele ieftine un bloc nou e mult peste restul pietei. In Warszawa locatia conteaza mai mult decat vechimea
-- Observatie: in 6 orase blocurile din 1990-2009 sunt mai ieftine decat cele de dinainte de 1990



-- H1. Ipoteza Lodz/Szczecin: are centrul mai multe cladiri vechi?
SELECT
    city,
    distance_band,
    COUNT(*)                                                                                         AS nr_apartamente,
    ROUND(100.0 * SUM(CASE WHEN building_age_group = 'Before 1990' THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_inainte_1990,
    ROUND(100.0 * SUM(CASE WHEN building_age_group = '2010+'       THEN 1 ELSE 0 END) / COUNT(*), 1) AS pct_2010_plus
FROM dbo.sales_clean
WHERE city IN ('Lodz', 'Szczecin')
GROUP BY city, distance_band
ORDER BY city,
         CASE distance_band WHEN '0-2 km' THEN 1 WHEN '2-5 km' THEN 2 WHEN '5-10 km' THEN 3 ELSE 4 END;

-- REZULTAT H1:
-- Lodz: centrul are doar 7,1% blocuri noi (vs 20,3% la 2-5 km) -> ipoteza CONFIRMATA:
--       centrul e mai ieftin pentru ca are mai putine cladiri noi
-- Szczecin: compozitie aproape identica (11,4% vs 12,6% blocuri noi) -> ipoteza NECONFIRMATA
-- Posibil starea cladirilor, dar coloana condition are 75% lipsa -> nu putem verifica



-- H2. Ipoteza boxa: e boxa mai frecventa in blocurile vechi?
SELECT
    building_age_group,
    COUNT(*)                                                                             AS nr_apartamente,
    ROUND(100.0 * SUM(CASE WHEN hasStorageRoom = 1 THEN 1 ELSE 0 END) / COUNT(*), 1)     AS pct_cu_boxa
FROM dbo.sales_clean
WHERE hasStorageRoom IS NOT NULL
GROUP BY building_age_group
ORDER BY building_age_group;

-- REZULTAT H2: boxa apare la 68,5% din apartamentele din blocuri vechi vs 14,2% in blocurile 2010+
-- -> ipoteza CONFIRMATA: boxa e un semn de bloc vechi, nu cauza pretului mai mic



-- Q5. Evolutia lunara a pretului median pe mp (pe toata oferta din fiecare luna)
WITH lunar AS (
    SELECT DISTINCT
        snapshot_month,
        COUNT(*) OVER (PARTITION BY snapshot_month)                         AS nr_anunturi,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price / squareMeters)
            OVER (PARTITION BY snapshot_month)                              AS median_pret_mp
    FROM dbo.sales_raw
)
SELECT
    snapshot_month,
    nr_anunturi,
    CAST(median_pret_mp AS DECIMAL(10,0))                                                  AS median_pret_mp,
    CAST(100.0 * (median_pret_mp / LAG(median_pret_mp) OVER (ORDER BY snapshot_month) - 1)
         AS DECIMAL(5,1))                                                                  AS variatie_lunara_pct
FROM lunar
ORDER BY snapshot_month;



-- Q5b. Verificare: aceeasi evolutie, doar pentru Warszawa (ca sa excludem schimbarea mixului de orase)
WITH lunar AS (
    SELECT DISTINCT
        snapshot_month,
        COUNT(*) OVER (PARTITION BY snapshot_month)                         AS nr_anunturi,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price / squareMeters)
            OVER (PARTITION BY snapshot_month)                              AS median_pret_mp
    FROM dbo.sales_raw
    WHERE city = 'warszawa'          -- in sales_raw orasele sunt cu litere mici
)
SELECT
    snapshot_month,
    nr_anunturi,
    CAST(median_pret_mp AS DECIMAL(10,0))                                                  AS median_pret_mp,
    CAST(100.0 * (median_pret_mp / LAG(median_pret_mp) OVER (ORDER BY snapshot_month) - 1)
         AS DECIMAL(5,1))                                                                  AS variatie_lunara_pct
FROM lunar
ORDER BY snapshot_month;

-- REZULTAT Q5 / Q5b (pret median cerut pe mp, toata oferta din fiecare luna):
-- CE: preturile au crescut in fiecare luna din aug 2023 pana in iun 2024, apoi cresterea a incetinit
-- CAT: national 11.383 -> 14.266 PLN/mp (+25,3%); Warszawa 14.713 -> 17.917 (+21,8%)
-- Cel mai mare salt: decembrie 2023 (+6,7% national, +5,0% Warszawa)
-- In 2024 cresterea scade sub 1-2%/luna (Warszawa: 0,0% in mai), iar oferta din Warszawa creste cu 57% (ian -> iun)
-- DECI: piata pare sa se stabilizeze in 2024: mai multa oferta, crestere de pret mai lenta
-- CONTEXT: programul Bezpieczny Kredyt 2% (start 3 iul 2023, cereri oprite 2 ian 2024) coincide cu perioada de crestere rapida.
--          Asociere in timp, NU dovada de cauzalitate
-- VERIFICARE: trendul se pastreaza si doar in Warszawa -> nu e doar efectul schimbarii mixului de orase
--            (ponderea Warszawa a crescut usor: 28,9% -> 32,4%)



-- Q6. Randamentul brut din chirie pe oras = chiria anuala / pretul de cumparare (ambele pe mp, mediane)
WITH vanzare AS (
    SELECT DISTINCT
        city,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm)
            OVER (PARTITION BY city)  AS pret_mp
    FROM dbo.sales_clean
),
chirie AS (
    SELECT DISTINCT
        city,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rent_per_sqm)
            OVER (PARTITION BY city)  AS chirie_lunara_mp
    FROM dbo.rent_clean
)
SELECT
    v.city,
    CAST(v.pret_mp AS DECIMAL(10,0))                                  AS pret_vanzare_mp,
    CAST(c.chirie_lunara_mp AS DECIMAL(10,1))                         AS chirie_lunara_mp,
    CAST(100.0 * c.chirie_lunara_mp * 12 / v.pret_mp AS DECIMAL(5,2)) AS randament_brut_pct,
    CAST(v.pret_mp / (c.chirie_lunara_mp * 12) AS DECIMAL(5,1))       AS ani_de_recuperare
FROM vanzare AS v
JOIN chirie  AS c ON v.city = c.city
ORDER BY randament_brut_pct DESC;

-- REZULTAT Q6 (randament brut = chirie anuala mediana / pret mediana, pe mp):
-- CE: orasele ieftine au cel mai mare randament din chirie, cele scumpe cel mai mic
-- CAT: Radom 7,43% (13,5 ani de recuperare), Czestochowa 7,34%, Katowice 7,13%
--      vs Krakow 5,13% (19,5 ani), Gdynia 5,62%, Warszawa 5,63%
-- Warszawa are cea mai mare chirie (78,7 PLN/mp/luna), dar pretul o face sa aiba randament mic.
-- DECI: pentru venit din chirie raportat la pret, orasele mici/medii sunt mai avantajoase
-- LIMITARI: randament BRUT (fara taxe, intretinere, perioade fara chirias); preturi si chirii CERUTE;
--           nu masoara riscul (cerere mai mica de chiriasi, lichiditate mai slaba in orasele mici)
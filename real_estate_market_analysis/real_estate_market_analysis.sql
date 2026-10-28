/* =========================================================
   1. Анализ времени активности объявлений
   ========================================================= */


/* ---------------------------------------------------------
   1.1. Подготовка данных
   --------------------------------------------------------- */

-- Определим границы аномальных значений для площади,
-- количества комнат, балконов и высоты потолков.

WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

-- Оставим объявления без аномальных значений.

filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE total_area < (SELECT total_area_limit FROM limits)
        AND (
            rooms < (SELECT rooms_limit FROM limits)
            OR rooms IS NULL
        )
        AND (
            balcony < (SELECT balcony_limit FROM limits)
            OR balcony IS NULL
        )
        AND (
            (
                ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
                AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
            )
            OR ceiling_height IS NULL
        )
),

flats_filtered AS (
    SELECT *
    FROM real_estate.flats
    WHERE id IN (SELECT id FROM filtered_id)
),

-- Добавим регион, категорию времени активности объявления
-- и стоимость квадратного метра.
-- В анализ включим только городские объявления за 2015-2018 годы.

flats_categorized AS (
    SELECT
        ff.id,
        ff.city_id,
        ff.type_id,
        ff.total_area,
        ff.rooms,
        ff.ceiling_height,
        ff.floors_total,
        ff.living_area,
        ff.floor,
        ff.is_apartment,
        ff.open_plan,
        ff.kitchen_area,
        ff.balcony,
        ff.airports_nearest,
        ff.parks_around3000,
        ff.ponds_around3000,
        CASE
            WHEN c.city = 'Санкт-Петербург'
                THEN 'Санкт-Петербург'
            ELSE 'Ленинградская обл.'
        END AS region,
        CASE
            WHEN a.days_exposition BETWEEN 1 AND 30
                THEN '1-30 days'
            WHEN a.days_exposition BETWEEN 31 AND 90
                THEN '31-90 days'
            WHEN a.days_exposition BETWEEN 91 AND 180
                THEN '91-180 days'
            WHEN a.days_exposition >= 181
                THEN '181+ days'
            ELSE 'non category'
        END AS activity,
        a.last_price::REAL / ff.total_area AS price_per_sqm,
        a.last_price
    FROM flats_filtered AS ff
    JOIN real_estate.advertisement AS a
        ON a.id = ff.id
    JOIN real_estate.city AS c
        ON c.city_id = ff.city_id
    JOIN real_estate.type AS t
        ON t.type_id = ff.type_id
    WHERE t.type = 'город'
        AND a.first_day_exposition >= '2015-01-01'
        AND a.first_day_exposition < '2019-01-01'
)


/* ---------------------------------------------------------
   1.2. Сравнение объявлений по времени активности
   --------------------------------------------------------- */

-- Для каждой категории сравним количество объявлений,
-- стоимость недвижимости и основные характеристики квартир
-- в Санкт-Петербурге и городах Ленинградской области.

SELECT
    region,
    activity,
    COUNT(*) AS flats_count,
    ROUND(
        COUNT(*)::NUMERIC
        / SUM(COUNT(*)) OVER (PARTITION BY region),
        2
    ) AS flats_share,
    ROUND(AVG(last_price)::NUMERIC, 2) AS avg_price,
    ROUND(AVG(price_per_sqm)::NUMERIC, 2) AS avg_price_per_sqm,
    ROUND(AVG(total_area)::NUMERIC, 2) AS avg_total_area,
    ROUND(AVG(kitchen_area)::NUMERIC, 2) AS avg_kitchen_area,
    ROUND(AVG(ceiling_height)::NUMERIC, 2) AS avg_ceiling_height,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balconies,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floor) AS median_floor,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floors_total) AS median_floors_total
FROM flats_categorized
GROUP BY region, activity
ORDER BY region DESC, activity;


/* =========================================================
   2. Анализ сезонности объявлений
   ========================================================= */


/* ---------------------------------------------------------
   2.1. Подготовка данных
   --------------------------------------------------------- */

-- Определим границы аномальных значений для площади,
-- количества комнат, балконов и высоты потолков.

WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

-- Оставим объявления без аномальных значений.

filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE total_area < (SELECT total_area_limit FROM limits)
        AND (
            rooms < (SELECT rooms_limit FROM limits)
            OR rooms IS NULL
        )
        AND (
            balcony < (SELECT balcony_limit FROM limits)
            OR balcony IS NULL
        )
        AND (
            (
                ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
                AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
            )
            OR ceiling_height IS NULL
        )
),

flats_filtered AS (
    SELECT *
    FROM real_estate.flats
    WHERE id IN (SELECT id FROM filtered_id)
),


/* ---------------------------------------------------------
   2.2. Сезонность публикации объявлений
   --------------------------------------------------------- */

-- Для каждого месяца рассчитаем количество опубликованных
-- объявлений, среднюю стоимость квартиры, стоимость квадратного
-- метра и среднюю площадь.
-- В анализ включим городские объявления за 2015-2018 годы.

monthly_advertisement_addition AS (
    SELECT
        TO_CHAR(
            TO_DATE(
                EXTRACT(MONTH FROM a.first_day_exposition)::TEXT,
                'MM'
            ),
            'Month'
        ) AS publication_month,
        COUNT(*) AS ads_published,
        ROUND(AVG(a.last_price)::NUMERIC, 2) AS avg_price_published,
        ROUND(
            AVG(a.last_price::REAL / f.total_area)::NUMERIC,
            2
        ) AS avg_price_per_sqm_published,
        ROUND(AVG(f.total_area)::NUMERIC, 2) AS avg_area_published,
        RANK() OVER (
            ORDER BY COUNT(*) DESC
        ) AS publication_rank
    FROM real_estate.advertisement AS a
    JOIN flats_filtered AS f
        ON f.id = a.id
    JOIN real_estate.type AS t
        ON t.type_id = f.type_id
    WHERE t.type = 'город'
        AND a.first_day_exposition >= '2015-01-01'
        AND a.first_day_exposition < '2019-01-01'
    GROUP BY publication_month
),


/* ---------------------------------------------------------
   2.3. Сезонность снятия объявлений
   --------------------------------------------------------- */

-- Рассчитаем месяц снятия объявления как дату публикации
-- плюс количество дней его активности.
-- Для каждого месяца рассчитаем те же показатели,
-- что и для опубликованных объявлений.

monthly_advertisement_removal AS (
    SELECT
        TO_CHAR(
            TO_DATE(
                EXTRACT(
                    MONTH
                    FROM a.first_day_exposition + a.days_exposition::INT
                )::TEXT,
                'MM'
            ),
            'Month'
        ) AS removal_month,
        COUNT(*) AS ads_removed,
        ROUND(AVG(a.last_price)::NUMERIC, 2) AS avg_price_removed,
        ROUND(
            AVG(a.last_price::REAL / f.total_area)::NUMERIC,
            2
        ) AS avg_price_per_sqm_removed,
        ROUND(AVG(f.total_area)::NUMERIC, 2) AS avg_area_removed,
        RANK() OVER (
            ORDER BY COUNT(*) DESC
        ) AS removal_rank
    FROM real_estate.advertisement AS a
    JOIN flats_filtered AS f
        ON f.id = a.id
    JOIN real_estate.type AS t
        ON t.type_id = f.type_id
    WHERE t.type = 'город'
        AND a.days_exposition IS NOT NULL
        AND a.first_day_exposition >= '2015-01-01'
        AND a.first_day_exposition < '2019-01-01'
    GROUP BY removal_month
)


/* ---------------------------------------------------------
   2.4. Сравнение публикации и снятия объявлений
   --------------------------------------------------------- */

-- Объединим показатели публикации и снятия объявлений
-- и добавим сезон для сравнения активности по месяцам.

SELECT
    CASE
        WHEN TRIM(p.publication_month) IN ('December', 'January', 'February')
            THEN 'Winter'
        WHEN TRIM(p.publication_month) IN ('March', 'April', 'May')
            THEN 'Spring'
        WHEN TRIM(p.publication_month) IN ('June', 'July', 'August')
            THEN 'Summer'
        WHEN TRIM(p.publication_month) IN ('September', 'October', 'November')
            THEN 'Autumn'
    END AS season,
    TRIM(p.publication_month) AS month,
    p.ads_published,
    p.publication_rank,
    r.ads_removed,
    r.removal_rank,
    p.avg_price_published,
    r.avg_price_removed,
    p.avg_price_per_sqm_published,
    r.avg_price_per_sqm_removed,
    p.avg_area_published,
    r.avg_area_removed
FROM monthly_advertisement_addition AS p
JOIN monthly_advertisement_removal AS r
    ON r.removal_month = p.publication_month
ORDER BY EXTRACT(
    MONTH FROM TO_DATE(TRIM(p.publication_month), 'Month')
);


/* =========================================================
   3. Дополнительный анализ населенных пунктов
   ========================================================= */


/* ---------------------------------------------------------
   3.1. Подготовка данных
   --------------------------------------------------------- */

-- Определим границы аномальных значений для площади,
-- количества комнат, балконов и высоты потолков.

WITH limits AS (
    SELECT
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats
),

-- Оставим объявления без аномальных значений.

filtered_id AS (
    SELECT id
    FROM real_estate.flats
    WHERE total_area < (SELECT total_area_limit FROM limits)
        AND (
            rooms < (SELECT rooms_limit FROM limits)
            OR rooms IS NULL
        )
        AND (
            balcony < (SELECT balcony_limit FROM limits)
            OR balcony IS NULL
        )
        AND (
            (
                ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
                AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)
            )
            OR ceiling_height IS NULL
        )
),

flats_filtered AS (
    SELECT *
    FROM real_estate.flats
    WHERE id IN (SELECT id FROM filtered_id)
),


/* ---------------------------------------------------------
   3.2. Показатели по населенным пунктам
   --------------------------------------------------------- */

-- Рассчитаем основные показатели для населенных пунктов
-- за пределами Санкт-Петербурга.
-- Для дальнейшего сравнения оставим 15 населенных пунктов
-- с наибольшим количеством снятых объявлений.

locality_stats AS (
    SELECT
        c.city AS locality,
        COUNT(*) AS ads_published,
        COUNT(a.days_exposition) AS ads_removed,
        ROUND(
            COUNT(a.days_exposition)::NUMERIC / COUNT(*),
            2
        ) AS ads_removed_share,
        ROUND(AVG(a.last_price)::NUMERIC, 2) AS avg_price,
        ROUND(
            AVG(a.last_price / f.total_area)::NUMERIC,
            2
        ) AS avg_price_per_sqm,
        ROUND(AVG(f.total_area)::NUMERIC, 2) AS avg_total_area,
        ROUND(AVG(f.kitchen_area)::NUMERIC, 2) AS avg_kitchen_area,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.rooms) AS median_rooms,
        ROUND(AVG(a.days_exposition)::NUMERIC) AS avg_days_exposition
    FROM real_estate.advertisement AS a
    JOIN flats_filtered AS f
        ON f.id = a.id
    JOIN real_estate.city AS c
        ON c.city_id = f.city_id
    WHERE c.city <> 'Санкт-Петербург'
    GROUP BY c.city
    ORDER BY ads_removed DESC
    LIMIT 15
),


/* ---------------------------------------------------------
   3.3. Скорость снятия объявлений
   --------------------------------------------------------- */

-- Определим границы трех групп по распределению среднего
-- времени активности объявлений среди выбранных населенных пунктов.

days_exposition_quantiles AS (
    SELECT
        PERCENTILE_CONT(0.33)
            WITHIN GROUP (ORDER BY avg_days_exposition) AS q33,
        PERCENTILE_CONT(0.66)
            WITHIN GROUP (ORDER BY avg_days_exposition) AS q66
    FROM locality_stats
)

-- Разделим населенные пункты на группы с относительно быстрым,
-- средним и медленным снятием объявлений.

SELECT
    locality,
    ads_published,
    ads_removed,
    ads_removed_share,
    avg_price,
    avg_price_per_sqm,
    avg_total_area,
    avg_kitchen_area,
    median_rooms,
    avg_days_exposition,
    CASE
        WHEN avg_days_exposition < q33
            THEN 'быстрая'
        WHEN avg_days_exposition < q66
            THEN 'умеренная'
        WHEN avg_days_exposition >= q66
            THEN 'медленная'
        ELSE 'нет данных'
    END AS removal_speed
FROM locality_stats
CROSS JOIN days_exposition_quantiles
ORDER BY ads_removed DESC;
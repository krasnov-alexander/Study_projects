/* =========================================================
   Анализ ключевых бизнес-метрик сервиса доставки еды
   Период: май - июнь 2021
   Город: Саранск
   ========================================================= */


/* =========================================================
   1. Активность пользователей
   ========================================================= */


/* ---------------------------------------------------------
   1.1. DAU по дням
   --------------------------------------------------------- */

-- Рассчитаем количество уникальных пользователей,
-- совершивших хотя бы один заказ в течение дня.

SELECT
    events.log_date AS date,
    COUNT(DISTINCT events.user_id) AS dau
FROM rest_analytics.analytics_events AS events
JOIN rest_analytics.cities AS cities
    ON events.city_id = cities.city_id
WHERE events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
    AND cities.city_name = 'Саранск'
    AND events.event = 'order'
GROUP BY events.log_date
ORDER BY events.log_date;


/* ---------------------------------------------------------
   1.2. MAU по месяцам
   --------------------------------------------------------- */

-- Рассчитаем количество уникальных пользователей,
-- совершивших хотя бы один заказ в течение месяца.

SELECT
    DATE_TRUNC('month', events.log_date)::date AS month,
    COUNT(DISTINCT events.user_id) AS mau
FROM rest_analytics.analytics_events AS events
JOIN rest_analytics.cities AS cities
    ON events.city_id = cities.city_id
WHERE events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
    AND cities.city_name = 'Саранск'
    AND events.event = 'order'
GROUP BY DATE_TRUNC('month', events.log_date)
ORDER BY month;


/* =========================================================
   2. Конверсия
   ========================================================= */


/* ---------------------------------------------------------
   2.1. Конверсия пользователей в заказ
   --------------------------------------------------------- */

-- Рассчитаем долю уникальных пользователей,
-- совершивших заказ, среди всех пользователей за каждый день.

SELECT
    events.log_date AS date,
    ROUND(
        COUNT(DISTINCT events.user_id)
            FILTER (WHERE events.event = 'order')
        / COUNT(DISTINCT events.user_id)::numeric,
        2
    ) AS conversion_rate
FROM rest_analytics.analytics_events AS events
JOIN rest_analytics.cities AS cities
    ON events.city_id = cities.city_id
WHERE events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
    AND cities.city_name = 'Саранск'
GROUP BY events.log_date
ORDER BY events.log_date;


/* =========================================================
   3. Монетизация
   ========================================================= */


/* ---------------------------------------------------------
   3.1. Количество заказов, комиссия и средний чек
   --------------------------------------------------------- */

-- Рассчитаем количество заказов, общую комиссию сервиса
-- и среднюю комиссию на один заказ отдельно для каждого месяца.

WITH orders AS (
    SELECT
        events.log_date,
        events.order_id,
        events.revenue * events.commission AS commission_revenue
    FROM rest_analytics.analytics_events AS events
    JOIN rest_analytics.cities AS cities
        ON events.city_id = cities.city_id
    WHERE events.revenue IS NOT NULL
        AND events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
        AND cities.city_name = 'Саранск'
)

SELECT
    DATE_TRUNC('month', log_date)::date AS month,
    COUNT(DISTINCT order_id) AS orders_count,
    ROUND(SUM(commission_revenue)::numeric, 2) AS total_commission,
    ROUND(
        (SUM(commission_revenue) / COUNT(DISTINCT order_id))::numeric,
        2
    ) AS avg_check
FROM orders
GROUP BY DATE_TRUNC('month', log_date)
ORDER BY month;


/* =========================================================
   4. LTV ресторанов и блюд
   ========================================================= */


/* ---------------------------------------------------------
   4.1. Топ-3 ресторанов по LTV
   --------------------------------------------------------- */

-- В рамках проекта LTV ресторана определяется как суммарная
-- комиссия сервиса от заказов ресторана за рассматриваемый период.

WITH orders AS (
    SELECT
        events.rest_id,
        events.city_id,
        events.revenue * events.commission AS commission_revenue
    FROM rest_analytics.analytics_events AS events
    JOIN rest_analytics.cities AS cities
        ON events.city_id = cities.city_id
    WHERE events.revenue IS NOT NULL
        AND events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
        AND cities.city_name = 'Саранск'
)

SELECT
    orders.rest_id,
    partners.chain AS restaurant_name,
    partners.type AS restaurant_type,
    ROUND(SUM(orders.commission_revenue)::numeric, 2) AS ltv
FROM orders
JOIN rest_analytics.partners AS partners
    ON orders.rest_id = partners.rest_id
    AND orders.city_id = partners.city_id
GROUP BY
    orders.rest_id,
    partners.chain,
    partners.type
ORDER BY ltv DESC
LIMIT 3;


/* ---------------------------------------------------------
   4.2. Топ-5 блюд по LTV
   --------------------------------------------------------- */

-- Выберем два ресторана с наибольшим LTV,
-- а затем определим пять блюд, принесших сервису
-- наибольшую комиссию в этих ресторанах.

WITH orders AS (
    SELECT
        events.rest_id,
        events.city_id,
        events.object_id,
        events.revenue * events.commission AS commission_revenue
    FROM rest_analytics.analytics_events AS events
    JOIN rest_analytics.cities AS cities
        ON events.city_id = cities.city_id
    WHERE events.revenue IS NOT NULL
        AND events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
        AND cities.city_name = 'Саранск'
),

top_ltv_restaurants AS (
    SELECT
        orders.rest_id,
        partners.chain,
        partners.type,
        SUM(orders.commission_revenue) AS ltv
    FROM orders
    JOIN rest_analytics.partners AS partners
        ON orders.rest_id = partners.rest_id
        AND orders.city_id = partners.city_id
    GROUP BY
        orders.rest_id,
        partners.chain,
        partners.type
    ORDER BY ltv DESC
    LIMIT 2
)

SELECT
    top_ltv_restaurants.chain AS restaurant_name,
    dishes.name AS dish_name,
    dishes.spicy,
    dishes.fish,
    dishes.meat,
    ROUND(SUM(orders.commission_revenue)::numeric, 2) AS ltv
FROM orders
JOIN top_ltv_restaurants
    ON orders.rest_id = top_ltv_restaurants.rest_id
JOIN rest_analytics.dishes AS dishes
    ON orders.object_id = dishes.object_id
    AND orders.rest_id = dishes.rest_id
GROUP BY
    top_ltv_restaurants.chain,
    dishes.name,
    dishes.spicy,
    dishes.fish,
    dishes.meat
ORDER BY ltv DESC
LIMIT 5;


/* =========================================================
   5. Удержание пользователей
   ========================================================= */


/* ---------------------------------------------------------
   5.1. Retention Rate первой недели
   --------------------------------------------------------- */

-- Рассчитаем долю новых пользователей, которые возвращались
-- в сервис в каждый из первых семи дней после первого посещения.

WITH new_users AS (
    SELECT DISTINCT
        events.first_date,
        events.user_id
    FROM rest_analytics.analytics_events AS events
    JOIN rest_analytics.cities AS cities
        ON events.city_id = cities.city_id
    WHERE events.first_date BETWEEN '2021-05-01' AND '2021-06-24'
        AND cities.city_name = 'Саранск'
),

active_users AS (
    SELECT DISTINCT
        events.log_date,
        events.user_id
    FROM rest_analytics.analytics_events AS events
    JOIN rest_analytics.cities AS cities
        ON events.city_id = cities.city_id
    WHERE events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
        AND cities.city_name = 'Саранск'
),

daily_retention AS (
    SELECT
        new_users.user_id,
        new_users.first_date,
        active_users.log_date::date - new_users.first_date::date
            AS day_since_first_visit
    FROM new_users
    JOIN active_users
        ON new_users.user_id = active_users.user_id
        AND active_users.log_date >= new_users.first_date
)

SELECT
    day_since_first_visit,
    COUNT(DISTINCT user_id) AS retained_users,
    ROUND(
        COUNT(DISTINCT user_id)::numeric
        / MAX(COUNT(DISTINCT user_id)) OVER (),
        2
    ) AS retention_rate
FROM daily_retention
WHERE day_since_first_visit BETWEEN 0 AND 7
GROUP BY day_since_first_visit
ORDER BY day_since_first_visit;


/* ---------------------------------------------------------
   5.2. Retention Rate по месячным когортам
   --------------------------------------------------------- */

-- Разделим новых пользователей на майскую и июньскую когорты
-- и сравним их Retention Rate в течение первой недели.

WITH new_users AS (
    SELECT DISTINCT
        events.first_date,
        events.user_id
    FROM rest_analytics.analytics_events AS events
    JOIN rest_analytics.cities AS cities
        ON events.city_id = cities.city_id
    WHERE events.first_date BETWEEN '2021-05-01' AND '2021-06-24'
        AND cities.city_name = 'Саранск'
),

active_users AS (
    SELECT DISTINCT
        events.log_date,
        events.user_id
    FROM rest_analytics.analytics_events AS events
    JOIN rest_analytics.cities AS cities
        ON events.city_id = cities.city_id
    WHERE events.log_date BETWEEN '2021-05-01' AND '2021-06-30'
        AND cities.city_name = 'Саранск'
),

daily_retention AS (
    SELECT
        new_users.user_id,
        new_users.first_date,
        active_users.log_date::date - new_users.first_date::date
            AS day_since_first_visit
    FROM new_users
    JOIN active_users
        ON new_users.user_id = active_users.user_id
        AND active_users.log_date >= new_users.first_date
),

cohort_retention AS (
    SELECT
        DATE_TRUNC('month', first_date)::date AS cohort_month,
        day_since_first_visit,
        COUNT(DISTINCT user_id) AS retained_users
    FROM daily_retention
    WHERE day_since_first_visit BETWEEN 0 AND 7
    GROUP BY
        DATE_TRUNC('month', first_date),
        day_since_first_visit
)

SELECT
    cohort_month,
    day_since_first_visit,
    retained_users,
    ROUND(
        retained_users::numeric
        / FIRST_VALUE(retained_users) OVER (
            PARTITION BY cohort_month
            ORDER BY day_since_first_visit
        ),
        2
    ) AS retention_rate
FROM cohort_retention
ORDER BY
    cohort_month,
    day_since_first_visit;
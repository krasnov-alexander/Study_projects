/* =========================================================
   1. Знакомство с данными и проверка их качества
   ========================================================= */


/* ---------------------------------------------------------
   1.1. Проверка данных об игроках
   --------------------------------------------------------- */

-- Проверим количество игроков и наличие пропусков в полях,
-- которые используются в дальнейшем анализе.

SELECT
    COUNT(*) AS users_count,
    COUNT(*) FILTER (WHERE class_id IS NULL) AS class_id_nulls,
    COUNT(*) FILTER (WHERE ch_id IS NULL) AS ch_id_nulls,
    COUNT(*) FILTER (WHERE pers_gender IS NULL) AS gender_nulls,
    COUNT(*) FILTER (WHERE server IS NULL) AS server_nulls,
    COUNT(*) FILTER (WHERE race_id IS NULL) AS race_id_nulls,
    COUNT(*) FILTER (WHERE payer IS NULL) AS payer_nulls,
    COUNT(*) FILTER (WHERE loc_id IS NULL) AS loc_id_nulls
FROM fantasy.users;


/* ---------------------------------------------------------
   1.2. Проверка данных о внутриигровых покупках
   --------------------------------------------------------- */

-- Проверим количество покупок и наличие пропусков в полях,
-- которые используются при анализе внутриигровых транзакций.

SELECT
    COUNT(*) AS transactions_count,
    COUNT(*) FILTER (WHERE date IS NULL) AS date_nulls,
    COUNT(*) FILTER (WHERE time IS NULL) AS time_nulls,
    COUNT(*) FILTER (WHERE amount IS NULL) AS amount_nulls,
    COUNT(*) FILTER (WHERE seller_id IS NULL) AS seller_id_nulls
FROM fantasy.events;


/* =========================================================
   2. Анализ монетизации игроков
   ========================================================= */


/* ---------------------------------------------------------
   2.1. Доля платящих игроков
   --------------------------------------------------------- */

-- Рассчитаем общее количество зарегистрированных игроков,
-- количество платящих игроков и их долю среди всех игроков.

SELECT
    COUNT(*) AS users_count,
    SUM(payer) AS payers_count,
    ROUND(AVG(payer), 3) AS payers_share
FROM fantasy.users;


/* ---------------------------------------------------------
   2.2. Доля платящих игроков по расам
   --------------------------------------------------------- */

-- Рассчитаем количество игроков и долю платящих
-- отдельно для каждой расы персонажа.

SELECT
    r.race,
    SUM(u.payer) AS payers_count,
    COUNT(*) AS users_count,
    ROUND(AVG(u.payer), 3) AS payers_share
FROM fantasy.users AS u
JOIN fantasy.race AS r USING (race_id)
GROUP BY r.race
ORDER BY payers_share DESC;


/* ---------------------------------------------------------
   2.3. Сравнение покупательского поведения платящих
        и неплатящих игроков
   --------------------------------------------------------- */

-- Для каждого покупателя рассчитаем количество покупок,
-- среднюю стоимость одной покупки и общую сумму покупок.
-- Покупки с нулевой стоимостью исключаем из анализа.

WITH user_activity AS (
    SELECT
        u.id,
        u.payer,
        COUNT(e.transaction_id) AS transactions_count,
        AVG(e.amount) AS avg_amount,
        SUM(e.amount) AS total_amount
    FROM fantasy.users AS u
    JOIN fantasy.events AS e USING (id)
    WHERE e.amount > 0
    GROUP BY u.id, u.payer
)

-- Сравним покупательскую активность игроков,
-- которые покупали игровую валюту за реальные деньги,
-- и остальных покупателей.

SELECT
    payer,
    COUNT(*) AS buyers_count,
    AVG(transactions_count) AS avg_transactions_per_buyer,
    AVG(avg_amount) AS avg_amount_per_buyer,
    AVG(total_amount) AS avg_total_amount_per_buyer
FROM user_activity
GROUP BY payer
ORDER BY payer DESC;


/* ---------------------------------------------------------
   2.4. Концентрация расходов среди покупателей
   --------------------------------------------------------- */

-- Рассчитаем суммарные расходы каждого покупателя
-- и определим его положение в рейтинге по объему расходов.

WITH user_spending AS (
    SELECT
        id,
        SUM(amount) AS total_amount
    FROM fantasy.events
    WHERE amount > 0
    GROUP BY id
),

ranked_users AS (
    SELECT
        id,
        total_amount,
        ROW_NUMBER() OVER (ORDER BY total_amount DESC) AS user_rank,
        COUNT(*) OVER () AS buyers_count,
        SUM(total_amount) OVER () AS all_spending
    FROM user_spending
)

-- Рассчитаем, какую долю всех расходов обеспечивают
-- топ-1%, топ-5% и топ-10% покупателей.

SELECT
    SUM(total_amount) FILTER (
        WHERE user_rank <= CEIL(buyers_count * 0.01)
    ) / MAX(all_spending) AS top_1_share,

    SUM(total_amount) FILTER (
        WHERE user_rank <= CEIL(buyers_count * 0.05)
    ) / MAX(all_spending) AS top_5_share,

    SUM(total_amount) FILTER (
        WHERE user_rank <= CEIL(buyers_count * 0.10)
    ) / MAX(all_spending) AS top_10_share
FROM ranked_users;


/* =========================================================
   3. Анализ внутриигровых покупок и предметов
   ========================================================= */


/* ---------------------------------------------------------
   3.1. Основные показатели внутриигровых покупок
   --------------------------------------------------------- */

-- Рассчитаем количество и суммарную стоимость покупок,
-- а также основные характеристики распределения их стоимости.

SELECT
    COUNT(*) AS transactions_count,
    SUM(amount) AS total_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    AVG(amount) AS avg_amount,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount) AS median_amount,
    STDDEV(amount) AS std_amount
FROM fantasy.events;


/* ---------------------------------------------------------
   3.2. Покупки с нулевой стоимостью
   --------------------------------------------------------- */

-- Проверим количество покупок с нулевой стоимостью
-- и рассчитаем их долю среди всех внутриигровых покупок.

SELECT
    COUNT(*) FILTER (WHERE amount = 0) AS zero_transactions_count,
    COUNT(*) AS transactions_count,
    COUNT(*) FILTER (WHERE amount = 0)::REAL / COUNT(*) AS zero_transactions_share
FROM fantasy.events;


/* ---------------------------------------------------------
   3.3. Популярность эпических предметов
   --------------------------------------------------------- */

-- Для каждого эпического предмета рассчитаем количество покупок
-- и количество уникальных игроков, которые его приобретали.
-- Покупки с нулевой стоимостью исключаем из анализа.

WITH item_stats AS (
    SELECT
        i.game_items,
        COUNT(e.transaction_id) AS transactions_count,
        COUNT(DISTINCT e.id) AS buyers_count
    FROM fantasy.items AS i
    LEFT JOIN fantasy.events AS e USING (item_code)
    WHERE e.amount > 0
    GROUP BY i.game_items
)

-- Рассчитаем долю покупок каждого предмета среди всех покупок
-- и долю его покупателей среди всех внутриигровых покупателей.

SELECT
    game_items,
    transactions_count,
    transactions_count::REAL / SUM(transactions_count) OVER () AS transactions_share,
    buyers_count::REAL / (
        SELECT COUNT(DISTINCT id)
        FROM fantasy.events
        WHERE amount > 0
    ) AS buyers_share
FROM item_stats
ORDER BY buyers_share DESC;


/* ---------------------------------------------------------
   3.4. Концентрация спроса на популярных предметах
   --------------------------------------------------------- */

-- Рассчитаем количество покупок каждого предмета.
-- Покупки с нулевой стоимостью исключаем из анализа.

WITH item_stats AS (
    SELECT
        i.game_items,
        COUNT(e.transaction_id) AS transactions_count
    FROM fantasy.items AS i
    JOIN fantasy.events AS e USING (item_code)
    WHERE e.amount > 0
    GROUP BY i.game_items
),

ranked_items AS (
    SELECT
        game_items,
        transactions_count,
        ROW_NUMBER() OVER (ORDER BY transactions_count DESC) AS item_rank,
        SUM(transactions_count) OVER () AS all_transactions
    FROM item_stats
)

-- Рассчитаем долю всех покупок, которая приходится
-- на топ-3, топ-5 и топ-10 наиболее популярных предметов.

SELECT
    SUM(transactions_count) FILTER (
        WHERE item_rank <= 3
    )::REAL / MAX(all_transactions) AS top_3_share,
    SUM(transactions_count) FILTER (
        WHERE item_rank <= 5
    )::REAL / MAX(all_transactions) AS top_5_share,
    SUM(transactions_count) FILTER (
        WHERE item_rank <= 10
    )::REAL / MAX(all_transactions) AS top_10_share
FROM ranked_items;


/* =========================================================
   4. Анализ покупательской активности по расам
   ========================================================= */


/* ---------------------------------------------------------
   4.1. Активность игроков по расам
   --------------------------------------------------------- */

-- Для каждой расы посчитаем общее количество зарегистрированных игроков.

WITH race_users AS (
    SELECT
        r.race,
        COUNT(u.id) AS users_count
    FROM fantasy.race AS r
    LEFT JOIN fantasy.users AS u USING (race_id)
    GROUP BY r.race
),

-- Для каждого игрока, совершившего хотя бы одну покупку,
-- рассчитаем количество покупок, их среднюю и суммарную стоимость.
-- Покупки с нулевой стоимостью исключаем из анализа.

user_activity AS (
    SELECT
        u.id,
        r.race,
        u.payer,
        COUNT(e.transaction_id) AS transactions_count,
        AVG(e.amount) AS avg_amount,
        SUM(e.amount) AS total_amount
    FROM fantasy.users AS u
    JOIN fantasy.race AS r USING (race_id)
    JOIN fantasy.events AS e USING (id)
    WHERE e.amount > 0
    GROUP BY u.id, r.race, u.payer
),

-- На основе показателей отдельных покупателей рассчитаем
-- характеристики покупательской активности для каждой расы.

race_activity AS (
    SELECT
        race,
        COUNT(*) AS buyers_count,
        AVG(payer) AS payers_share_among_buyers,
        AVG(transactions_count) AS avg_transactions_per_buyer,
        AVG(avg_amount) AS avg_amount_per_buyer,
        AVG(total_amount) AS avg_total_amount_per_buyer
    FROM user_activity
    GROUP BY race
)

-- Объединим количество зарегистрированных игроков
-- с показателями покупательской активности по каждой расе.

SELECT
    ru.race,
    ru.users_count,
    ra.buyers_count,
    ra.buyers_count::REAL / ru.users_count AS buyers_share,
    ra.payers_share_among_buyers,
    ra.avg_transactions_per_buyer,
    ra.avg_amount_per_buyer,
    ra.avg_total_amount_per_buyer
FROM race_users AS ru
JOIN race_activity AS ra USING (race)
ORDER BY ru.race;
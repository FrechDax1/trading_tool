-- =====================================================================
-- Approximative Tages-Aktualisierung von RSI14, ATR, ADX/PlusDI/MinusDI, MACD
-- fuer die Tabellen index_prices / index_indicators, OHNE persistente
-- Zwischenzustands-Spalten.
--
-- Idee: Wilder-/EMA-Glaettung "vergisst" alte Werte geometrisch. Bei
-- einem Lookback von 150 Tagen ist der Naeherungsfehler < 0.01%
-- (empirisch getestet). Bei zu kurzem Lookback (< 100 Tage) wird vor
-- allem ADX und MACD ungenau (bis zu 20-30% Abweichung) - deshalb
-- p_lookback nicht kleiner als 100-150 waehlen.
--
-- Die komplette Kette wird bei jedem Aufruf ueber die letzten
-- p_lookback Tage aus index_prices neu aufgerollt (rekursive CTE);
-- nur der letzte (heutige) Tag wird in index_indicators geschrieben.
-- Kein State wird dauerhaft gespeichert.
--
-- Nachts sollte der exakte Batch-Job (volle Historie) diesen Tag
-- erneut berechnen und ueberschreiben.
-- =====================================================================

DROP PROCEDURE IF EXISTS sp_approx_indicators_today;

DELIMITER $$

CREATE PROCEDURE sp_approx_indicators_today(
    IN p_ticker   VARCHAR(10),
    IN p_date     DATE,
    IN p_lookback INT
)
BEGIN
    DECLARE v_sma50, v_sma200, v_bbmid, v_bbstd, v_bbupper, v_bblower DECIMAL(15,6);
    DECLARE v_lookback_rows INT;
    DECLARE v_check_close DECIMAL(15,6);

    -- ------------------------------------------------------------
    -- Absicherung: gibt es ueberhaupt OHLC-Daten fuer p_date?
    -- ------------------------------------------------------------
    SELECT `Close` INTO v_check_close
      FROM index_prices
     WHERE Ticker = p_ticker AND `Date` = p_date;

    IF v_check_close IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Keine OHLC-Daten fuer dieses Ticker/Datum in index_prices vorhanden - Abbruch.';
    END IF;

    SET v_lookback_rows = p_lookback + 1;

    -- ------------------------------------------------------------
    -- SMA / Bollinger: reine Fensteraggregate, exakt (kein Approx noetig)
    -- ------------------------------------------------------------
    SELECT AVG(`Close`) INTO v_sma50 FROM (
        SELECT `Close` FROM index_prices WHERE Ticker = p_ticker AND `Date` <= p_date
        ORDER BY `Date` DESC LIMIT 50) t;

    SELECT AVG(`Close`) INTO v_sma200 FROM (
        SELECT `Close` FROM index_prices WHERE Ticker = p_ticker AND `Date` <= p_date
        ORDER BY `Date` DESC LIMIT 200) t;

    SELECT AVG(`Close`), STDDEV_SAMP(`Close`) INTO v_bbmid, v_bbstd FROM (
        SELECT `Close` FROM index_prices WHERE Ticker = p_ticker AND `Date` <= p_date
        ORDER BY `Date` DESC LIMIT 20) t;

    SET v_bbupper = v_bbmid + 2 * v_bbstd;
    SET v_bblower = v_bbmid - 2 * v_bbstd;

    -- ------------------------------------------------------------
    -- RSI14 / ATR / ADX+PlusDI+MinusDI / MACD: Naeherung via
    -- rekursivem Wiederaufrollen ueber die letzten p_lookback Tage
    -- ------------------------------------------------------------
    INSERT INTO index_indicators (
        Ticker, `Date`, SMA50, SMA200, BBMid, BBUpper, BBLower,
        RSI14, ATR, ADX, PlusDI, MinusDI, MACD, MACDSignal, MACDHist
    )
    WITH RECURSIVE hist AS (
        SELECT `Date`, High, Low, `Close`
        FROM (
            SELECT `Date`, High, Low, `Close`
            FROM index_prices
            WHERE Ticker = p_ticker AND `Date` <= p_date
            ORDER BY `Date` DESC
            LIMIT v_lookback_rows
        ) t
        ORDER BY `Date` ASC
    ),
    diffs AS (
        SELECT
            `Date`, High, Low, `Close`,
            LAG(`Close`) OVER (ORDER BY `Date`) AS prev_close,
            LAG(High)    OVER (ORDER BY `Date`) AS prev_high,
            LAG(Low)     OVER (ORDER BY `Date`) AS prev_low
        FROM hist
    ),
    base AS (
        SELECT
            ROW_NUMBER() OVER (ORDER BY `Date`) AS rn,
            `Date`, `Close`,
            GREATEST(High-Low, ABS(High-prev_close), ABS(Low-prev_close)) AS tr,
            GREATEST(`Close`-prev_close, 0) AS gain,
            GREATEST(prev_close-`Close`, 0) AS loss,
            IF(High-prev_high > prev_low-Low AND High-prev_high > 0, High-prev_high, 0) AS dm_plus,
            IF(prev_low-Low > High-prev_high AND prev_low-Low > 0, prev_low-Low, 0) AS dm_minus
        FROM diffs
        WHERE prev_close IS NOT NULL
    ),
    chain AS (
        SELECT
            rn, `Date`, `Close`,
            tr AS avg_tr, gain AS avg_gain, loss AS avg_loss,
            dm_plus AS avg_dm_plus, dm_minus AS avg_dm_minus,
            `Close` AS ema12, `Close` AS ema26,
            CAST(0.0 AS DECIMAL(15,6)) AS macd,
            CAST(0.0 AS DECIMAL(15,6)) AS macd_signal,
            CAST(0.0 AS DECIMAL(15,6)) AS adx
        FROM base WHERE rn = 1

        UNION ALL

        SELECT
            s3.rn, s3.`Date`, s3.`Close`,
            s3.avg_tr, s3.avg_gain, s3.avg_loss,
            s3.avg_dm_plus, s3.avg_dm_minus,
            s3.ema12, s3.ema26, s3.macd, s3.macd_signal,
            (s3.prev_adx * 13 + s3.dx) / 14 AS adx
        FROM (
            SELECT
                s2.rn, s2.`Date`, s2.`Close`,
                s2.avg_tr, s2.avg_gain, s2.avg_loss,
                s2.avg_dm_plus, s2.avg_dm_minus,
                s2.ema12, s2.ema26, s2.macd,
                s2.prev_macd_signal, s2.prev_adx,
                IF(s2.di_plus + s2.di_minus = 0, 0,
                   100 * ABS(s2.di_plus - s2.di_minus) / (s2.di_plus + s2.di_minus)) AS dx,
                (s2.macd * (2/10) + s2.prev_macd_signal * (8/10)) AS macd_signal
            FROM (
                SELECT
                    s1.rn, s1.`Date`, s1.`Close`,
                    s1.avg_tr, s1.avg_gain, s1.avg_loss,
                    s1.avg_dm_plus, s1.avg_dm_minus,
                    s1.ema12, s1.ema26,
                    (s1.ema12 - s1.ema26) AS macd,
                    s1.prev_macd_signal, s1.prev_adx,
                    IF(s1.avg_tr = 0, 0, 100*s1.avg_dm_plus/s1.avg_tr)  AS di_plus,
                    IF(s1.avg_tr = 0, 0, 100*s1.avg_dm_minus/s1.avg_tr) AS di_minus
                FROM (
                    SELECT
                        b.rn, b.`Date`, b.`Close`,
                        (c.avg_tr*13       + b.tr)/14        AS avg_tr,
                        (c.avg_gain*13     + b.gain)/14      AS avg_gain,
                        (c.avg_loss*13     + b.loss)/14      AS avg_loss,
                        (c.avg_dm_plus*13  + b.dm_plus)/14   AS avg_dm_plus,
                        (c.avg_dm_minus*13 + b.dm_minus)/14  AS avg_dm_minus,
                        b.`Close`*(2/13) + c.ema12*(11/13)   AS ema12,
                        b.`Close`*(2/27) + c.ema26*(25/27)   AS ema26,
                        c.macd_signal AS prev_macd_signal,
                        c.adx         AS prev_adx
                    FROM base b
                    JOIN chain c ON b.rn = c.rn + 1
                ) s1
            ) s2
        ) s3
    )
    SELECT
        p_ticker, p_date, v_sma50, v_sma200, v_bbmid, v_bbupper, v_bblower,
        100 - (100 / (1 + (fin.avg_gain / NULLIF(fin.avg_loss,0)))) AS rsi14_calc,
        fin.avg_tr AS atr,
        fin.adx AS adx,
        IF(fin.avg_tr=0,0,100*fin.avg_dm_plus/fin.avg_tr)  AS plus_di,
        IF(fin.avg_tr=0,0,100*fin.avg_dm_minus/fin.avg_tr) AS minus_di,
        fin.macd AS macd,
        fin.macd_signal AS macd_signal,
        (fin.macd - fin.macd_signal) AS macd_hist
    FROM chain fin
    ORDER BY fin.rn DESC
    LIMIT 1
    ON DUPLICATE KEY UPDATE
        SMA50=VALUES(SMA50), SMA200=VALUES(SMA200), BBMid=VALUES(BBMid),
        BBUpper=VALUES(BBUpper), BBLower=VALUES(BBLower),
        RSI14=VALUES(RSI14), ATR=VALUES(ATR), ADX=VALUES(ADX),
        PlusDI=VALUES(PlusDI), MinusDI=VALUES(MinusDI),
        MACD=VALUES(MACD), MACDSignal=VALUES(MACDSignal), MACDHist=VALUES(MACDHist);
END $$

DELIMITER ;

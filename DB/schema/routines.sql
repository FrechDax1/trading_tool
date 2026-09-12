/*M!999999\- enable the sandbox mode */ 
-- MariaDB dump 10.19  Distrib 10.11.18-MariaDB, for debian-linux-gnu (x86_64)
--
-- Host: 195.35.53.19    Database: u903087946_Q4Y
-- ------------------------------------------------------
-- Server version	11.8.9-MariaDB-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Dumping routines for database 'u903087946_Q4Y'
--
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `refresh_daily_sar` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`u903087946_Q4Y`@`127.0.0.1` PROCEDURE `refresh_daily_sar`()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_ticker VARCHAR(10);
    DECLARE v_date DATE;
    DECLARE v_open, v_high, v_low, v_close DECIMAL(16, 4);

    -- Variablen für SAR
    DECLARE p_sar DECIMAL(16, 4);
    DECLARE p_ep DECIMAL(16, 4);
    
    -- REDUZIERTE AF-PARAMETER (ca. 1/5 der Standardwerte)
    DECLARE c_af_start DECIMAL(16, 4) DEFAULT 0.004; -- Startwert
    DECLARE c_af_step DECIMAL(16, 4) DEFAULT 0.004;  -- Schrittweite
    DECLARE c_af_max DECIMAL(16, 4) DEFAULT 0.040;   -- Max-Wert
    
    DECLARE p_af DECIMAL(16, 4);
    DECLARE p_is_uptrend TINYINT(1);
    DECLARE curr_ticker VARCHAR(10) DEFAULT '';

    -- Cursor liest direkt Tagesdaten
    DECLARE cur CURSOR FOR 
        SELECT 
            Ticker,
            Date,
            Open,
            High,
            Low,
            Close
        FROM `u903087946_Q4Y`.`index_prices`
        ORDER BY Ticker, Date ASC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    TRUNCATE TABLE daily_index_price_sar;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO v_ticker, v_date, v_open, v_high, v_low, v_close;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Bei neuem Ticker: Initialisierung
        IF curr_ticker != v_ticker THEN
            SET curr_ticker = v_ticker;
            SET p_is_uptrend = IF(v_close >= v_open, 1, 0);
            SET p_sar = IF(p_is_uptrend = 1, v_low, v_high);
            SET p_ep = IF(p_is_uptrend = 1, v_high, v_low);
            SET p_af = c_af_start;
        ELSE
            -- SAR-Formel
            SET p_sar = p_sar + p_af * (p_ep - p_sar);

            -- Trendwechsel prüfen & AF anpassen
            IF p_is_uptrend = 1 THEN
                IF v_low < p_sar THEN
                    SET p_is_uptrend = 0;
                    SET p_sar = p_ep;
                    SET p_ep = v_low;
                    SET p_af = c_af_start;
                ELSE
                    IF v_high > p_ep THEN
                        SET p_ep = v_high;
                        SET p_af = LEAST(c_af_max, p_af + c_af_step);
                    END IF;
                END IF;
            ELSE
                IF v_high > p_sar THEN
                    SET p_is_uptrend = 1;
                    SET p_sar = p_ep;
                    SET p_ep = v_high;
                    SET p_af = c_af_start;
                ELSE
                    IF v_low < p_ep THEN
                        SET p_ep = v_low;
                        SET p_af = LEAST(c_af_max, p_af + c_af_step);
                    END IF;
                END IF;
            END IF;
        END IF;

        INSERT INTO daily_index_price_sar (Ticker, Date, sar, is_uptrend)
        VALUES (v_ticker, v_date, p_sar, p_is_uptrend);

    END LOOP;

    CLOSE cur;
END
;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!50003 SET @saved_sql_mode       = @@sql_mode */ ;
/*!50003 SET sql_mode              = 'NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION' */ ;
/*!50003 DROP PROCEDURE IF EXISTS `refresh_weekly_sar` */;
/*!50003 SET @saved_cs_client      = @@character_set_client */ ;
/*!50003 SET @saved_cs_results     = @@character_set_results */ ;
/*!50003 SET @saved_col_connection = @@collation_connection */ ;
/*!50003 SET character_set_client  = utf8mb4 */ ;
/*!50003 SET character_set_results = utf8mb4 */ ;
/*!50003 SET collation_connection  = utf8mb4_unicode_ci */ ;
DELIMITER ;;
CREATE DEFINER=`u903087946_Q4Y`@`127.0.0.1` PROCEDURE `refresh_weekly_sar`()
BEGIN
    DECLARE done INT DEFAULT FALSE;
    DECLARE v_ticker VARCHAR(10);
    DECLARE v_yearweek INT;
    DECLARE v_week_start DATE;
    DECLARE v_open, v_high, v_low, v_close DECIMAL(16, 4);

    -- Variablen für die SAR-Berechnungslogik
    DECLARE p_sar DECIMAL(16, 4);
    DECLARE p_ep DECIMAL(16, 4);
    DECLARE p_af DECIMAL(16, 4) DEFAULT 0.02;
    DECLARE p_is_uptrend TINYINT(1);
    
    DECLARE curr_ticker VARCHAR(10) DEFAULT '';

    -- Cursor liest nun aus der korrekt benannten Tabelle u903087946_Q4Y.index_prices
    DECLARE cur CURSOR FOR 
        SELECT 
            Ticker,
            YEARWEEK(Date, 1) AS yw,
            MIN(Date) AS w_start,
            SUBSTRING_INDEX(GROUP_CONCAT(Open ORDER BY Date ASC), ',', 1) AS w_open,
            MAX(High) AS w_high,
            MIN(Low) AS w_low,
            SUBSTRING_INDEX(GROUP_CONCAT(Close ORDER BY Date DESC), ',', 1) AS w_close
        FROM `u903087946_Q4Y`.`index_prices`
        GROUP BY Ticker, YEARWEEK(Date, 1)
        ORDER BY Ticker, YEARWEEK(Date, 1) ASC;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = TRUE;

    -- Vorhandene Daten in der Ziel-Tabelle leeren
    TRUNCATE TABLE weekly_index_price_sar;

    OPEN cur;

    read_loop: LOOP
        FETCH cur INTO v_ticker, v_yearweek, v_week_start, v_open, v_high, v_low, v_close;
        IF done THEN
            LEAVE read_loop;
        END IF;

        -- Bei Ticker-Wechsel SAR neu initialisieren
        IF curr_ticker != v_ticker THEN
            SET curr_ticker = v_ticker;
            SET p_is_uptrend = IF(v_close >= v_open, 1, 0);
            SET p_sar = IF(p_is_uptrend = 1, v_low, v_high);
            SET p_ep = IF(p_is_uptrend = 1, v_high, v_low);
            SET p_af = 0.02;
        ELSE
            -- SAR-Formel anwenden
            SET p_sar = p_sar + p_af * (p_ep - p_sar);

            -- Trendwechsel prüfen & Acceleration Factor anpassen
            IF p_is_uptrend = 1 THEN
                IF v_low < p_sar THEN
                    SET p_is_uptrend = 0;
                    SET p_sar = p_ep;
                    SET p_ep = v_low;
                    SET p_af = 0.02;
                ELSE
                    IF v_high > p_ep THEN
                        SET p_ep = v_high;
                        SET p_af = LEAST(0.20, p_af + 0.02);
                    END IF;
                END IF;
            ELSE
                IF v_high > p_sar THEN
                    SET p_is_uptrend = 1;
                    SET p_sar = p_ep;
                    SET p_ep = v_high;
                    SET p_af = 0.02;
                ELSE
                    IF v_low < p_ep THEN
                        SET p_ep = v_low;
                        SET p_af = LEAST(0.20, p_af + 0.02);
                    END IF;
                END IF;
            END IF;
        END IF;

        -- In Ziel-Tabelle einfügen
        INSERT INTO weekly_index_price_sar (Ticker, year_week, week_start, sar, is_uptrend)
        VALUES (v_ticker, v_yearweek, v_week_start, p_sar, p_is_uptrend);

    END LOOP;

    CLOSE cur;
END
;;
DELIMITER ;
/*!50003 SET sql_mode              = @saved_sql_mode */ ;
/*!50003 SET character_set_client  = @saved_cs_client */ ;
/*!50003 SET character_set_results = @saved_cs_results */ ;
/*!50003 SET collation_connection  = @saved_col_connection */ ;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed

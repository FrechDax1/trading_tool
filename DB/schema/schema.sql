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
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `aktien_lookup`
--

DROP TABLE IF EXISTS `aktien_lookup`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `aktien_lookup` (
  `isin` varchar(20) NOT NULL,
  `wkn` varchar(10) NOT NULL,
  `ticker` varchar(20) NOT NULL,
  `name` varchar(255) NOT NULL,
  `ariva_url` varchar(255) NOT NULL,
  PRIMARY KEY (`isin`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `aktionen`
--

DROP TABLE IF EXISTS `aktionen`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `aktionen` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `empfehlung_id` int(11) DEFAULT NULL,
  `basiswert_ticker` varchar(20) NOT NULL,
  `aktion` enum('Kauf','Verkauf') NOT NULL,
  `wkn` varchar(10) NOT NULL,
  `typ` enum('Call','Put') NOT NULL DEFAULT 'Call',
  `knockout_schwelle` decimal(10,4) DEFAULT NULL,
  `hebel` decimal(6,2) DEFAULT NULL,
  `emittent` varchar(50) DEFAULT NULL,
  `stueckzahl` decimal(10,4) NOT NULL,
  `kaufkurs_produkt` decimal(10,4) NOT NULL,
  `verkaufskurs_produkt` decimal(10,4) DEFAULT NULL,
  `datum` date NOT NULL,
  `verkaufsdatum` date DEFAULT NULL,
  `gebuehren` decimal(10,2) DEFAULT 0.00,
  `notiz` text DEFAULT NULL,
  `erstellt_am` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `empfehlung_id` (`empfehlung_id`),
  CONSTRAINT `aktionen_ibfk_1` FOREIGN KEY (`empfehlung_id`) REFERENCES `empfehlungen` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `daily_index_price_sar`
--

DROP TABLE IF EXISTS `daily_index_price_sar`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_index_price_sar` (
  `Ticker` varchar(10) NOT NULL,
  `Date` date NOT NULL,
  `sar` decimal(16,4) DEFAULT NULL,
  `is_uptrend` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`Ticker`,`Date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `empfehlungen`
--

DROP TABLE IF EXISTS `empfehlungen`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `empfehlungen` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `bezeichnung` varchar(255) NOT NULL,
  `ticker` varchar(20) NOT NULL,
  `isin` varchar(20) NOT NULL,
  `ordertyp` varchar(20) NOT NULL,
  `gueltigkeit` varchar(50) NOT NULL,
  `preis` decimal(10,2) DEFAULT NULL,
  `handelstag` date NOT NULL,
  `notiz` text DEFAULT NULL,
  `eingefuegt_am` datetime NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_empfehlung` (`isin`,`handelstag`)
) ENGINE=InnoDB AUTO_INCREMENT=20 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_uca1400_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `index_indicators`
--

DROP TABLE IF EXISTS `index_indicators`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `index_indicators` (
  `Ticker` varchar(10) NOT NULL,
  `Date` date NOT NULL,
  `RSI14` decimal(10,4) DEFAULT NULL,
  `SMA50` decimal(15,6) DEFAULT NULL,
  `SMA200` decimal(15,6) DEFAULT NULL,
  `BBMid` decimal(15,6) DEFAULT NULL,
  `BBUpper` decimal(15,6) DEFAULT NULL,
  `BBLower` decimal(15,6) DEFAULT NULL,
  `MACD` decimal(15,6) DEFAULT NULL,
  `MACDSignal` decimal(15,6) DEFAULT NULL,
  `MACDHist` decimal(15,6) DEFAULT NULL,
  `ADX` decimal(15,6) DEFAULT NULL,
  `ATR` decimal(15,6) DEFAULT NULL,
  `PlusDI` decimal(15,6) DEFAULT NULL,
  `MinusDI` decimal(15,6) DEFAULT NULL,
  PRIMARY KEY (`Ticker`,`Date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `index_prices`
--

DROP TABLE IF EXISTS `index_prices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `index_prices` (
  `Ticker` varchar(10) NOT NULL,
  `Date` date NOT NULL,
  `Open` decimal(15,6) DEFAULT NULL,
  `High` decimal(15,6) DEFAULT NULL,
  `Low` decimal(15,6) DEFAULT NULL,
  `Close` decimal(15,6) DEFAULT NULL,
  `Volume` bigint(20) NOT NULL,
  PRIMARY KEY (`Ticker`,`Date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `market_sentiment`
--

DROP TABLE IF EXISTS `market_sentiment`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `market_sentiment` (
  `date` date NOT NULL,
  `source` varchar(20) NOT NULL DEFAULT 'CBOE',
  `symbol` varchar(30) NOT NULL DEFAULT 'EQUITY_PC',
  `value` decimal(12,6) DEFAULT NULL,
  PRIMARY KEY (`date`,`source`,`symbol`),
  KEY `idx_symbol_date` (`symbol`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `market_sentiment_bak`
--

DROP TABLE IF EXISTS `market_sentiment_bak`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `market_sentiment_bak` (
  `date` date NOT NULL,
  `source` varchar(20) NOT NULL,
  `symbol` varchar(30) NOT NULL,
  `value` decimal(12,6) DEFAULT NULL,
  PRIMARY KEY (`date`,`source`,`symbol`),
  KEY `idx_symbol_date` (`symbol`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `market_sentiment_symbols`
--

DROP TABLE IF EXISTS `market_sentiment_symbols`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `market_sentiment_symbols` (
  `symbol` varchar(30) NOT NULL,
  `source` varchar(20) NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `frequency` varchar(20) DEFAULT NULL,
  `unit` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`source`,`symbol`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `ticker_symbols`
--

DROP TABLE IF EXISTS `ticker_symbols`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `ticker_symbols` (
  `ticker_symbol` varchar(30) NOT NULL,
  `ticker_symbol_long` varchar(100) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`ticker_symbol`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Table structure for table `weekly_index_price_sar`
--

DROP TABLE IF EXISTS `weekly_index_price_sar`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8mb4 */;
CREATE TABLE `weekly_index_price_sar` (
  `Ticker` varchar(10) NOT NULL,
  `year_week` int(11) NOT NULL,
  `week_start` date NOT NULL,
  `sar` decimal(16,4) DEFAULT NULL,
  `is_uptrend` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`Ticker`,`year_week`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
/*!40101 SET character_set_client = @saved_cs_client */;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed

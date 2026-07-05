-- MySQL dump 10.13  Distrib 8.0.45, for Linux (x86_64)
--
-- Host: localhost    Database: im
-- ------------------------------------------------------
-- Server version	8.0.45

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `account_deletion_audits`
--

DROP TABLE IF EXISTS `account_deletion_audits`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `account_deletion_audits` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_uuid` char(36) COLLATE utf8mb4_general_ci NOT NULL,
  `mongo_status` varchar(32) COLLATE utf8mb4_general_ci NOT NULL,
  `mongo_deleted_count` bigint NOT NULL DEFAULT '0',
  `local_files_deleted` bigint NOT NULL DEFAULT '0',
  `local_files_failed` bigint NOT NULL DEFAULT '0',
  `external_queued_count` bigint NOT NULL DEFAULT '0',
  `external_cleanup_hint` varchar(64) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending_or_not_configured',
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_account_deletion_audits_user_uuid` (`user_uuid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `account_deletion_audits`
--

LOCK TABLES `account_deletion_audits` WRITE;
/*!40000 ALTER TABLE `account_deletion_audits` DISABLE KEYS */;
/*!40000 ALTER TABLE `account_deletion_audits` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `account_deletion_external_tasks`
--

DROP TABLE IF EXISTS `account_deletion_external_tasks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `account_deletion_external_tasks` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_uuid` char(36) COLLATE utf8mb4_general_ci NOT NULL,
  `resource_url` varchar(2048) COLLATE utf8mb4_general_ci NOT NULL,
  `status` varchar(32) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `retry_count` bigint NOT NULL DEFAULT '0',
  `next_retry_at` datetime DEFAULT NULL,
  `last_error` varchar(500) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `finished_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_account_deletion_external_tasks_user_uuid` (`user_uuid`),
  KEY `idx_account_deletion_external_tasks_status` (`status`),
  KEY `idx_account_deletion_external_tasks_next_retry_at` (`next_retry_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `account_deletion_external_tasks`
--

LOCK TABLES `account_deletion_external_tasks` WRITE;
/*!40000 ALTER TABLE `account_deletion_external_tasks` DISABLE KEYS */;
/*!40000 ALTER TABLE `account_deletion_external_tasks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `admin_login_logs`
--

DROP TABLE IF EXISTS `admin_login_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `admin_login_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `admin_id` bigint unsigned NOT NULL,
  `ip` varchar(50) DEFAULT NULL,
  `user_agent` varchar(500) DEFAULT NULL,
  `status` tinyint DEFAULT '1',
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_admin_login_logs_admin_id` (`admin_id`)
) ENGINE=InnoDB AUTO_INCREMENT=15 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `admin_login_logs`
--

LOCK TABLES `admin_login_logs` WRITE;
/*!40000 ALTER TABLE `admin_login_logs` DISABLE KEYS */;
INSERT INTO `admin_login_logs` VALUES (1,1,'74.207.241.28','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-16 06:14:06'),(2,1,'151.240.13.42','Mozilla/5.0 (iPhone; CPU iPhone OS 18_6_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/149.0.7827.137 Mobile/15E148 Safari/604.1',1,'2026-06-16 06:35:40'),(3,1,'45.119.135.147','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',1,'2026-06-16 15:11:05'),(4,1,'74.207.241.28','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-18 09:59:34'),(5,1,'38.45.126.162','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 Edg/149.0.0.0',1,'2026-06-19 05:51:51'),(6,1,'38.45.126.162','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',1,'2026-06-20 14:20:20'),(7,1,'35.78.78.4','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-21 11:00:46'),(8,1,'146.70.14.23','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-23 04:38:12'),(9,1,'45.83.137.20','Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36 Edg/149.0.0.0',1,'2026-06-26 10:53:42'),(10,1,'58.152.33.217','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/148.0.0.0 Safari/537.36',1,'2026-06-27 17:33:19'),(11,1,'210.79.151.66','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-28 09:42:28'),(12,1,'210.79.151.66','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-28 14:45:27'),(13,1,'210.79.151.66','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-30 15:20:50'),(14,1,'210.79.151.66','Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36',1,'2026-06-30 15:20:57');
/*!40000 ALTER TABLE `admin_login_logs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `admins`
--

DROP TABLE IF EXISTS `admins`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `admins` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `username` varchar(50) NOT NULL,
  `password` varchar(100) NOT NULL,
  `nickname` varchar(100) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `avatar` varchar(500) DEFAULT NULL,
  `role` varchar(20) NOT NULL DEFAULT 'admin',
  `status` tinyint DEFAULT '1',
  `last_login_at` datetime DEFAULT NULL,
  `last_login_ip` varchar(50) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_admins_username` (`username`),
  UNIQUE KEY `idx_admins_email` (`email`),
  KEY `idx_admins_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `admins`
--

LOCK TABLES `admins` WRITE;
/*!40000 ALTER TABLE `admins` DISABLE KEYS */;
INSERT INTO `admins` VALUES (1,'admin','$2a$10$8f.ZGUB06Cmytkj3QYH9t.ACflVH50.OG8esB09X6b2/eiVoLoIxq','超级管理员','admin@gaoranim.com',NULL,'super_admin',1,'2026-06-30 15:20:57','210.79.151.66','2026-06-16 05:23:27','2026-06-30 15:20:57',NULL),(2,'demo','$2a$10$oPg.CyASUzK8kyT6vLyFBuFtGFhGWc/Mm3bokT8zK.r4AO8pXVmlC','演示管理员','demo@gaoranim.com',NULL,'demo_admin',1,NULL,NULL,'2026-06-16 05:23:27','2026-06-16 05:23:27',NULL);
/*!40000 ALTER TABLE `admins` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `banned_words`
--

DROP TABLE IF EXISTS `banned_words`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `banned_words` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `word` varchar(100) NOT NULL,
  `category` varchar(50) DEFAULT NULL,
  `level` tinyint DEFAULT '1',
  `replacement` varchar(100) DEFAULT NULL,
  `status` tinyint DEFAULT '1',
  `hit_count` bigint DEFAULT '0',
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_banned_words_word` (`word`),
  KEY `idx_banned_words_category` (`category`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `banned_words`
--

LOCK TABLES `banned_words` WRITE;
/*!40000 ALTER TABLE `banned_words` DISABLE KEYS */;
INSERT INTO `banned_words` VALUES (1,'找死','other',2,'',1,1,'2026-06-16 16:13:31.683','2026-06-16 16:13:31.683'),(2,'日了狗','other',3,'',1,1,'2026-06-16 16:14:22.204','2026-06-16 16:14:53.471');
/*!40000 ALTER TABLE `banned_words` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `call_participants`
--

DROP TABLE IF EXISTS `call_participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_participants` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `call_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `user_uuid` varchar(36) NOT NULL,
  `join_time` datetime(3) DEFAULT NULL,
  `leave_time` datetime(3) DEFAULT NULL,
  `duration` bigint DEFAULT '0',
  `is_muted` tinyint(1) DEFAULT '0',
  `is_video_off` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_call_participants_user_id` (`user_id`),
  KEY `idx_call_participants_user_uuid` (`user_uuid`),
  KEY `idx_call_participants_deleted_at` (`deleted_at`),
  KEY `idx_call_participants_call_id` (`call_id`),
  CONSTRAINT `fk_call_participants_call` FOREIGN KEY (`call_id`) REFERENCES `call_records` (`id`),
  CONSTRAINT `fk_call_participants_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `call_participants`
--

LOCK TABLES `call_participants` WRITE;
/*!40000 ALTER TABLE `call_participants` DISABLE KEYS */;
/*!40000 ALTER TABLE `call_participants` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `call_records`
--

DROP TABLE IF EXISTS `call_records`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `call_records` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `uuid` varchar(36) NOT NULL,
  `room_id` varchar(100) NOT NULL,
  `caller_id` bigint unsigned NOT NULL,
  `caller_uuid` varchar(36) NOT NULL,
  `callee_id` bigint unsigned NOT NULL,
  `callee_uuid` varchar(36) NOT NULL,
  `chat_id` varchar(36) DEFAULT NULL,
  `call_type` tinyint DEFAULT '1',
  `status` tinyint DEFAULT '0',
  `start_time` datetime(3) DEFAULT NULL,
  `end_time` datetime(3) DEFAULT NULL,
  `duration` bigint DEFAULT '0',
  `end_reason` varchar(50) DEFAULT NULL,
  `caller_ip` varchar(50) DEFAULT NULL,
  `callee_ip` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_call_records_uuid` (`uuid`),
  KEY `idx_call_records_callee_uuid` (`callee_uuid`),
  KEY `idx_call_records_chat_id` (`chat_id`),
  KEY `idx_call_records_deleted_at` (`deleted_at`),
  KEY `idx_call_records_room_id` (`room_id`),
  KEY `idx_call_records_caller_id` (`caller_id`),
  KEY `idx_call_records_caller_uuid` (`caller_uuid`),
  KEY `idx_call_records_callee_id` (`callee_id`),
  CONSTRAINT `fk_call_records_callee` FOREIGN KEY (`callee_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_call_records_caller` FOREIGN KEY (`caller_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `call_records`
--

LOCK TABLES `call_records` WRITE;
/*!40000 ALTER TABLE `call_records` DISABLE KEYS */;
/*!40000 ALTER TABLE `call_records` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `calls`
--

DROP TABLE IF EXISTS `calls`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `calls` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `channel_name` varchar(100) DEFAULT NULL,
  `caller_id` bigint unsigned DEFAULT NULL,
  `callee_id` bigint unsigned DEFAULT NULL,
  `call_type` varchar(20) DEFAULT NULL,
  `status` varchar(20) DEFAULT NULL,
  `start_time` datetime(3) DEFAULT NULL,
  `connect_time` datetime(3) DEFAULT NULL,
  `end_time` datetime(3) DEFAULT NULL,
  `duration` bigint DEFAULT NULL,
  `end_reason` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_calls_deleted_at` (`deleted_at`),
  KEY `idx_calls_channel_name` (`channel_name`),
  KEY `idx_calls_caller_id` (`caller_id`),
  KEY `idx_calls_callee_id` (`callee_id`),
  CONSTRAINT `fk_calls_callee` FOREIGN KEY (`callee_id`) REFERENCES `users` (`id`),
  CONSTRAINT `fk_calls_caller` FOREIGN KEY (`caller_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=25 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `calls`
--

LOCK TABLES `calls` WRITE;
/*!40000 ALTER TABLE `calls` DISABLE KEYS */;
INSERT INTO `calls` VALUES (1,'2026-06-27 18:13:34.747','2026-06-27 18:13:45.986',NULL,'call_1d413183_8c0ae608_1782555214',31,3,'voice','cancelled','2026-06-27 18:13:34.747','0000-00-00 00:00:00.000','2026-06-27 18:13:45.986',0,'cancelled'),(2,'2026-06-27 18:14:25.381','2026-06-27 18:14:50.660',NULL,'call_1d413183_657c488c_1782555265',31,16,'video','cancelled','2026-06-27 18:14:25.381','0000-00-00 00:00:00.000','2026-06-27 18:14:50.660',0,'cancelled'),(3,'2026-06-27 20:11:28.915','2026-06-27 20:14:10.810',NULL,'call_1d413183_9a6bd42b_1782562288',31,4,'video','ended','2026-06-27 20:11:28.915','2026-06-27 20:11:39.640','2026-06-27 20:14:10.810',151,'hangup'),(4,'2026-06-27 20:14:15.841','2026-06-27 20:15:00.014',NULL,'call_1d413183_9a6bd42b_1782562455',31,4,'voice','ended','2026-06-27 20:14:15.841','2026-06-27 20:14:21.359','2026-06-27 20:15:00.014',38,'hangup'),(5,'2026-06-27 20:15:05.753','2026-06-27 20:15:51.264',NULL,'call_1d413183_9a6bd42b_1782562505',31,4,'video','ended','2026-06-27 20:15:05.753','2026-06-27 20:15:09.815','2026-06-27 20:15:51.264',41,'hangup'),(6,'2026-06-27 20:15:55.215','2026-06-27 20:16:08.496',NULL,'call_1d413183_9a6bd42b_1782562555',31,4,'video','ended','2026-06-27 20:15:55.214','2026-06-27 20:15:57.818','2026-06-27 20:16:08.496',10,'hangup'),(7,'2026-06-27 20:16:14.936','2026-06-27 20:16:35.192',NULL,'call_1d413183_9a6bd42b_1782562574',4,31,'voice','ended','2026-06-27 20:16:14.936','2026-06-27 20:16:17.149','2026-06-27 20:16:35.192',18,'hangup'),(8,'2026-06-27 20:16:38.537','2026-06-27 20:17:08.074',NULL,'call_1d413183_9a6bd42b_1782562598',4,31,'video','ended','2026-06-27 20:16:38.537','2026-06-27 20:16:41.874','2026-06-27 20:17:08.074',26,'hangup'),(9,'2026-06-27 20:17:16.306','2026-06-27 20:18:05.419',NULL,'call_1d413183_9a6bd42b_1782562636',4,31,'video','ended','2026-06-27 20:17:16.306','2026-06-27 20:17:24.125','2026-06-27 20:18:05.418',41,'hangup'),(10,'2026-06-27 20:28:27.982','2026-06-27 20:29:06.715',NULL,'call_1d413183_8c0ae608_1782563307',31,3,'video','ended','2026-06-27 20:28:27.982','2026-06-27 20:28:34.187','2026-06-27 20:29:06.715',32,'hangup'),(11,'2026-06-27 20:29:10.232','2026-06-27 20:29:37.818',NULL,'call_1d413183_8c0ae608_1782563350',31,3,'voice','ended','2026-06-27 20:29:10.232','2026-06-27 20:29:15.018','2026-06-27 20:29:37.818',22,'hangup'),(12,'2026-06-27 20:29:41.074','2026-06-27 20:30:12.911',NULL,'call_1d413183_8c0ae608_1782563381',31,3,'video','ended','2026-06-27 20:29:41.074','2026-06-27 20:29:42.889','2026-06-27 20:30:12.911',30,'hangup'),(13,'2026-06-27 20:49:41.951','2026-06-27 20:49:46.830',NULL,'call_1d413183_8c0ae608_1782564581',31,3,'voice','cancelled','2026-06-27 20:49:41.951','0000-00-00 00:00:00.000','2026-06-27 20:49:46.829',0,'cancelled'),(14,'2026-06-27 20:49:48.869','2026-06-27 20:49:54.100',NULL,'call_1d413183_8c0ae608_1782564588',31,3,'video','cancelled','2026-06-27 20:49:48.869','0000-00-00 00:00:00.000','2026-06-27 20:49:54.100',0,'cancelled'),(15,'2026-06-27 21:39:30.049','2026-06-27 21:40:33.044',NULL,'call_2db61135_fc387b56_1782567570',25,26,'voice','ended','2026-06-27 21:39:30.049','2026-06-27 21:39:33.832','2026-06-27 21:40:33.044',59,'hangup'),(16,'2026-06-27 21:40:43.280','2026-06-27 21:41:43.836',NULL,'call_2db61135_fc387b56_1782567643',25,26,'video','ended','2026-06-27 21:40:43.280','2026-06-27 21:40:54.772','2026-06-27 21:41:43.836',49,'hangup'),(17,'2026-06-27 22:12:56.501','2026-06-27 22:13:07.721',NULL,'call_e5119442_fc387b56_1782569576',27,25,'voice','ended','2026-06-27 22:12:56.501','0000-00-00 00:00:00.000','2026-06-27 22:13:07.721',0,'hangup'),(18,'2026-06-28 08:48:17.472','2026-06-28 08:48:25.171',NULL,'call_e5119442_fc387b56_1782607697',27,25,'voice','cancelled','2026-06-28 08:48:17.472','0000-00-00 00:00:00.000','2026-06-28 08:48:25.171',0,'cancelled'),(19,'2026-06-28 08:48:32.465','2026-06-28 08:48:52.498',NULL,'call_2db61135_fc387b56_1782607712',25,26,'voice','cancelled','2026-06-28 08:48:32.465','0000-00-00 00:00:00.000','2026-06-28 08:48:52.498',0,'cancelled'),(20,'2026-06-28 08:49:03.994','2026-06-28 08:49:12.333',NULL,'call_2db61135_fc387b56_1782607743',25,26,'video','cancelled','2026-06-28 08:49:03.994','0000-00-00 00:00:00.000','2026-06-28 08:49:12.333',0,'cancelled'),(21,'2026-06-28 08:49:18.147','2026-06-28 08:49:46.946',NULL,'call_e5119442_fc387b56_1782607758',25,27,'voice','ended','2026-06-28 08:49:18.147','2026-06-28 08:49:29.731','2026-06-28 08:49:46.946',17,'hangup'),(22,'2026-06-28 08:57:49.875','2026-06-28 08:58:32.730',NULL,'call_e5119442_fc387b56_1782608269',27,25,'video','ended','2026-06-28 08:57:49.875','2026-06-28 08:58:28.873','2026-06-28 08:58:32.730',3,'hangup'),(23,'2026-06-28 08:58:42.792','2026-06-28 08:58:49.059',NULL,'call_e5119442_fc387b56_1782608322',27,25,'video','ended','2026-06-28 08:58:42.792','2026-06-28 08:58:44.804','2026-06-28 08:58:49.059',4,'hangup'),(24,'2026-06-28 08:59:01.698','2026-06-28 08:59:32.056',NULL,'call_e5119442_fc387b56_1782608341',27,25,'voice','ended','2026-06-28 08:59:01.698','2026-06-28 08:59:05.196','2026-06-28 08:59:32.056',26,'hangup');
/*!40000 ALTER TABLE `calls` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `chat_announcements`
--

DROP TABLE IF EXISTS `chat_announcements`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `chat_announcements` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `chat_id` bigint unsigned NOT NULL,
  `content` text COLLATE utf8mb4_general_ci NOT NULL,
  `author_id` bigint unsigned NOT NULL,
  `is_pinned` tinyint(1) DEFAULT '1',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_chat_announcements_deleted_at` (`deleted_at`),
  KEY `idx_chat_announcements_chat_id` (`chat_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `chat_announcements`
--

LOCK TABLES `chat_announcements` WRITE;
/*!40000 ALTER TABLE `chat_announcements` DISABLE KEYS */;
/*!40000 ALTER TABLE `chat_announcements` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `chat_members`
--

DROP TABLE IF EXISTS `chat_members`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `chat_members` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `chat_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `role` tinyint DEFAULT '0',
  `nickname` varchar(100) DEFAULT NULL,
  `is_muted` tinyint(1) DEFAULT '0',
  `is_pinned` tinyint(1) DEFAULT '0',
  `mute_end_time` datetime DEFAULT NULL,
  `last_read_seq` bigint unsigned DEFAULT '0',
  `joined_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_chat_user` (`chat_id`,`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=153 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `chat_members`
--

LOCK TABLES `chat_members` WRITE;
/*!40000 ALTER TABLE `chat_members` DISABLE KEYS */;
INSERT INTO `chat_members` VALUES (1,1,4,0,'',0,0,NULL,0,'2026-06-16 15:49:56','2026-06-16 15:49:56'),(2,1,3,0,'',0,0,NULL,0,'2026-06-16 15:49:56','2026-06-16 15:49:56'),(3,2,3,2,'',0,0,NULL,0,'2026-06-16 15:55:20','2026-06-16 15:55:20'),(4,2,4,0,'',0,0,NULL,0,'2026-06-16 15:55:20','2026-06-16 15:55:20'),(5,3,3,2,'',0,0,NULL,0,'2026-06-16 16:22:31','2026-06-16 16:22:31'),(6,4,3,2,'',0,0,NULL,0,'2026-06-16 16:27:09','2026-06-16 16:27:09'),(7,4,4,0,'',0,0,NULL,0,'2026-06-17 01:58:15','2026-06-17 01:58:15'),(8,3,4,0,'',0,0,NULL,0,'2026-06-17 01:58:39','2026-06-17 01:58:39'),(9,5,6,0,'',0,0,NULL,0,'2026-06-17 14:26:04','2026-06-17 14:26:04'),(10,5,1,0,'',0,0,NULL,0,'2026-06-17 14:26:04','2026-06-17 14:26:04'),(11,6,17,0,'',0,0,NULL,0,'2026-06-19 05:54:59','2026-06-19 05:54:59'),(12,6,16,0,'',0,0,NULL,0,'2026-06-19 05:54:59','2026-06-19 05:54:59'),(13,7,17,2,'',0,0,NULL,0,'2026-06-19 05:58:59','2026-06-19 05:58:59'),(14,7,16,0,'',0,0,NULL,0,'2026-06-19 06:01:10','2026-06-19 06:01:10'),(15,8,16,2,'',0,0,NULL,0,'2026-06-19 06:40:40','2026-06-19 06:40:40'),(16,9,6,2,'',0,0,NULL,0,'2026-06-19 07:37:33','2026-06-19 07:37:33'),(17,9,1,0,'',0,0,NULL,0,'2026-06-19 07:38:56','2026-06-19 07:38:56'),(18,10,6,0,'',0,0,NULL,0,'2026-06-19 08:17:21','2026-06-19 08:17:21'),(19,10,18,0,'',0,0,NULL,0,'2026-06-19 08:17:21','2026-06-19 08:17:21'),(20,11,3,0,'',0,0,NULL,0,'2026-06-20 14:36:32','2026-06-20 14:36:32'),(21,11,16,0,'',0,0,NULL,0,'2026-06-20 14:36:32','2026-06-20 14:36:32'),(22,12,6,2,'',0,0,NULL,0,'2026-06-22 03:15:53','2026-06-22 03:15:53'),(23,12,1,0,'',0,0,NULL,0,'2026-06-22 03:15:53','2026-06-22 03:15:53'),(24,12,18,0,'',0,0,NULL,0,'2026-06-22 03:15:53','2026-06-22 03:15:53'),(25,13,22,0,'',0,0,NULL,0,'2026-06-22 10:52:46','2026-06-22 10:52:46'),(26,13,21,0,'',0,0,NULL,0,'2026-06-22 10:52:46','2026-06-22 10:52:46'),(27,14,21,2,'',0,0,NULL,0,'2026-06-22 10:54:11','2026-06-22 10:54:11'),(28,15,1,0,'',0,0,NULL,0,'2026-06-22 10:56:33','2026-06-22 10:56:33'),(29,15,7,0,'',0,0,NULL,0,'2026-06-22 10:56:33','2026-06-22 10:56:33'),(30,16,6,0,'',0,0,NULL,0,'2026-06-22 10:56:34','2026-06-22 10:56:34'),(31,16,7,0,'',0,0,NULL,0,'2026-06-22 10:56:34','2026-06-22 10:56:34'),(32,14,22,0,'',0,0,NULL,0,'2026-06-22 10:56:44','2026-06-22 10:56:44'),(33,17,1,0,'',0,0,NULL,0,'2026-06-22 10:57:02','2026-06-22 10:57:02'),(34,17,8,0,'',0,0,NULL,0,'2026-06-22 10:57:02','2026-06-22 10:57:02'),(35,18,6,0,'',0,0,NULL,0,'2026-06-22 10:57:03','2026-06-22 10:57:03'),(36,18,8,0,'',0,0,NULL,0,'2026-06-22 10:57:03','2026-06-22 10:57:03'),(37,19,1,0,'',0,0,NULL,0,'2026-06-22 10:57:30','2026-06-22 10:57:30'),(38,19,9,0,'',0,0,NULL,0,'2026-06-22 10:57:30','2026-06-22 10:57:30'),(39,20,6,0,'',0,0,NULL,0,'2026-06-22 10:57:49','2026-06-22 10:57:49'),(40,20,10,0,'',0,0,NULL,0,'2026-06-22 10:57:49','2026-06-22 10:57:49'),(41,21,1,0,'',0,0,NULL,0,'2026-06-22 10:57:49','2026-06-22 10:57:49'),(42,21,10,0,'',0,0,NULL,0,'2026-06-22 10:57:49','2026-06-22 10:57:49'),(43,22,1,0,'',0,0,NULL,0,'2026-06-22 10:58:18','2026-06-22 10:58:18'),(44,22,11,0,'',0,0,NULL,0,'2026-06-22 10:58:18','2026-06-22 10:58:18'),(45,23,6,0,'',0,0,NULL,0,'2026-06-22 10:58:18','2026-06-22 10:58:18'),(46,23,11,0,'',0,0,NULL,0,'2026-06-22 10:58:18','2026-06-22 10:58:18'),(47,24,21,2,'',0,0,NULL,0,'2026-06-22 10:58:31','2026-06-22 10:58:31'),(48,24,22,1,'',0,0,NULL,0,'2026-06-22 10:58:31','2026-06-22 11:00:00'),(49,25,1,0,'',0,0,NULL,0,'2026-06-22 10:58:57','2026-06-22 10:58:57'),(50,25,12,0,'',0,0,NULL,0,'2026-06-22 10:58:57','2026-06-22 10:58:57'),(52,26,1,0,'',0,0,NULL,0,'2026-06-22 11:03:27','2026-06-22 11:03:27'),(53,26,22,0,'',0,0,NULL,0,'2026-06-22 11:03:27','2026-06-22 11:03:27'),(54,27,1,0,'',0,0,NULL,0,'2026-06-22 11:06:12','2026-06-22 11:06:12'),(55,27,21,0,'',0,0,NULL,0,'2026-06-22 11:06:12','2026-06-22 11:06:12'),(57,12,24,0,'',0,0,NULL,0,'2026-06-22 11:23:15','2026-06-22 11:23:15'),(58,28,24,0,'',0,0,NULL,0,'2026-06-22 11:24:16','2026-06-22 11:24:16'),(59,28,6,0,'',0,0,NULL,0,'2026-06-22 11:24:16','2026-06-22 11:24:16'),(60,12,25,0,'',0,0,NULL,0,'2026-06-23 04:22:21','2026-06-23 04:22:21'),(61,12,26,0,'',0,0,NULL,0,'2026-06-23 04:47:08','2026-06-23 04:47:08'),(62,12,27,0,'',0,0,NULL,0,'2026-06-23 04:47:35','2026-06-23 04:47:35'),(63,29,25,0,'',0,0,NULL,0,'2026-06-23 04:47:56','2026-06-23 04:47:56'),(64,29,26,0,'',0,0,NULL,0,'2026-06-23 04:47:56','2026-06-23 04:47:56'),(65,30,25,0,'',0,0,NULL,0,'2026-06-23 04:48:21','2026-06-23 04:48:21'),(66,30,27,0,'',0,0,NULL,0,'2026-06-23 04:48:21','2026-06-23 04:48:21'),(67,31,1,0,'',0,0,NULL,0,'2026-06-23 07:55:53','2026-06-23 07:55:53'),(68,31,25,0,'',0,0,NULL,0,'2026-06-23 07:55:53','2026-06-23 07:55:53'),(69,12,28,0,'',0,0,NULL,0,'2026-06-23 08:39:38','2026-06-23 08:39:38'),(70,32,28,0,'',0,0,NULL,0,'2026-06-23 09:06:49','2026-06-23 09:06:49'),(71,32,1,0,'',0,0,NULL,0,'2026-06-23 09:06:49','2026-06-23 09:06:49'),(72,33,28,2,'',0,0,NULL,0,'2026-06-23 09:08:01','2026-06-23 09:08:01'),(74,12,29,0,'',0,0,NULL,0,'2026-06-25 02:12:16','2026-06-25 02:12:16'),(75,34,29,0,'',0,0,NULL,0,'2026-06-25 02:13:35','2026-06-25 02:13:35'),(76,34,4,0,'',0,0,NULL,0,'2026-06-25 02:13:35','2026-06-25 02:13:35'),(77,35,29,0,'',0,0,NULL,0,'2026-06-25 02:14:56','2026-06-25 02:14:56'),(78,35,3,0,'',0,0,NULL,0,'2026-06-25 02:14:56','2026-06-25 02:14:56'),(79,12,30,0,'',0,0,NULL,0,'2026-06-25 02:16:12','2026-06-25 02:16:12'),(80,36,30,0,'',0,0,NULL,0,'2026-06-25 02:17:04','2026-06-25 02:17:04'),(81,36,4,0,'',0,0,NULL,0,'2026-06-25 02:17:04','2026-06-25 02:17:04'),(82,12,31,0,'',0,0,NULL,0,'2026-06-25 02:18:55','2026-06-25 02:18:55'),(83,37,30,0,'',0,0,NULL,0,'2026-06-25 02:28:18','2026-06-25 02:28:18'),(84,37,3,0,'',0,0,NULL,0,'2026-06-25 02:28:18','2026-06-25 02:28:18'),(85,38,31,0,'',0,0,NULL,0,'2026-06-25 02:28:18','2026-06-25 02:28:18'),(86,38,3,0,'',0,0,NULL,0,'2026-06-25 02:28:18','2026-06-25 02:28:18'),(87,4,31,0,'',0,0,NULL,0,'2026-06-25 02:30:57','2026-06-25 02:30:57'),(88,39,31,0,'',0,0,NULL,0,'2026-06-25 02:32:44','2026-06-25 02:32:44'),(89,39,4,0,'',0,0,NULL,0,'2026-06-25 02:32:44','2026-06-25 02:32:44'),(90,40,6,2,'',0,0,NULL,0,'2026-06-25 14:21:53','2026-06-25 14:21:53'),(92,41,25,2,'',0,0,NULL,0,'2026-06-25 14:44:52','2026-06-25 14:44:52'),(93,41,26,0,'',0,0,NULL,0,'2026-06-25 14:44:52','2026-06-25 14:44:52'),(94,41,27,1,'',0,0,NULL,0,'2026-06-25 14:44:52','2026-06-25 14:45:46'),(140,40,1,0,'',0,0,NULL,0,'2026-06-25 18:22:32','2026-06-25 18:22:32'),(141,42,25,0,'',0,0,NULL,0,'2026-06-26 14:56:56','2026-06-26 14:56:56'),(142,42,28,0,'',0,0,NULL,0,'2026-06-26 14:56:56','2026-06-26 14:56:56'),(143,43,31,0,'',0,0,NULL,0,'2026-06-27 18:14:51','2026-06-27 18:14:51'),(144,43,16,0,'',0,0,NULL,0,'2026-06-27 18:14:51','2026-06-27 18:14:51'),(145,44,31,0,'',0,0,NULL,0,'2026-06-27 18:14:58','2026-06-27 18:14:58'),(146,44,25,0,'',0,0,NULL,0,'2026-06-27 18:14:58','2026-06-27 18:14:58'),(147,45,27,0,'',0,0,NULL,0,'2026-06-28 08:59:39','2026-06-28 08:59:39'),(148,45,26,0,'',0,0,NULL,0,'2026-06-28 08:59:39','2026-06-28 08:59:39'),(149,12,32,0,'',0,0,NULL,0,'2026-06-28 14:30:52','2026-06-28 14:30:52'),(150,46,25,2,'',0,0,NULL,0,'2026-06-28 15:51:59','2026-06-28 15:51:59'),(151,47,25,2,'',0,0,NULL,0,'2026-06-28 15:52:37','2026-06-28 15:52:37'),(152,47,27,0,'',0,0,NULL,0,'2026-06-28 15:52:37','2026-06-28 15:52:37');
/*!40000 ALTER TABLE `chat_members` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `chats`
--

DROP TABLE IF EXISTS `chats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `chats` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` char(36) NOT NULL,
  `type` tinyint NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `avatar` varchar(500) DEFAULT NULL,
  `description` varchar(1000) DEFAULT NULL,
  `owner_id` bigint unsigned DEFAULT NULL,
  `member_count` bigint DEFAULT '0',
  `max_members` bigint DEFAULT '200',
  `is_public` tinyint(1) DEFAULT '0',
  `invite_link` varchar(100) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `status` tinyint DEFAULT '0',
  `ban_reason` varchar(500) DEFAULT NULL,
  `banned_at` datetime DEFAULT NULL,
  `username` varchar(32) DEFAULT NULL,
  `can_send_message` tinyint(1) DEFAULT '1',
  `can_send_media` tinyint(1) DEFAULT '1',
  `can_send_links` tinyint(1) DEFAULT '1',
  `can_add_members` tinyint(1) DEFAULT '0',
  `can_pin_messages` tinyint(1) DEFAULT '0',
  `member_protection` tinyint(1) DEFAULT '1',
  `join_approval` tinyint(1) DEFAULT '0',
  `pinned_message_id` varchar(36) DEFAULT '',
  `pinned_message_text` varchar(500) DEFAULT NULL,
  `pinned_message_by` bigint unsigned DEFAULT '0',
  `pinned_message_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_chats_uuid` (`uuid`),
  UNIQUE KEY `idx_chats_invite_link` (`invite_link`),
  KEY `idx_chats_deleted_at` (`deleted_at`),
  KEY `idx_chats_owner_id` (`owner_id`),
  KEY `idx_chats_username` (`username`)
) ENGINE=InnoDB AUTO_INCREMENT=48 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `chats`
--

LOCK TABLES `chats` WRITE;
/*!40000 ALTER TABLE `chats` DISABLE KEYS */;
INSERT INTO `chats` VALUES (1,'4b32c553-5a0a-46e3-9bd2-cf0015ec3bfd',1,'','','',0,2,200,0,'ca63e09b','2026-06-16 15:49:56','2026-06-16 15:49:56',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(2,'32ee047e-1dfa-4a1f-9fe2-24633dff7806',2,'测试111','','555',3,2,200000,1,'3735abdb','2026-06-16 15:55:20','2026-06-16 16:09:48',NULL,0,'',NULL,'z4545',0,1,1,0,1,1,1,'','',0,NULL),(3,'50e1b0f7-1992-4d8a-b5cd-03e0e296f458',3,'测试频道112255','','11',3,2,200,1,'bb2a59bf','2026-06-16 16:22:31','2026-06-25 02:29:18',NULL,0,'',NULL,'p1111',1,1,1,0,0,1,0,'','',0,NULL),(4,'dae5c8c7-c2de-4154-92a9-0292c780d13e',3,'公开频道2266888','','223',3,3,200,1,'18ae7cb0','2026-06-16 16:27:09','2026-06-25 02:30:57',NULL,0,'',NULL,'p11112222',1,1,1,0,0,1,0,'','',0,NULL),(5,'e4b49391-b2a2-49d6-8f86-3240b010e20a',1,'','','',0,2,200,0,'12bd5670','2026-06-17 14:26:04','2026-06-17 14:26:04',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(6,'ab5e776e-3114-43e2-b8d8-e77982c990c7',1,'','','',0,2,200,0,'713c6838','2026-06-19 05:54:59','2026-06-19 05:54:59','2026-06-22 10:44:36.809',0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(7,'134db0a3-836c-45bb-ab50-33954c5fe74c',3,'111','','111111',17,2,200,1,'140ab5e1','2026-06-19 05:58:59','2026-06-19 06:01:10',NULL,0,'',NULL,'ces11111',1,1,1,0,0,1,0,'','',0,NULL),(8,'053eb7b8-e99e-4a52-8385-7055172f6ce2',3,'1','','1111',16,1,200,1,'fe3ff5b1','2026-06-19 06:40:40','2026-06-19 06:40:40',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(9,'5720aafc-f39e-446f-9e69-1d22c48796e1',3,'cspd','','',6,2,200,1,'37ae580c','2026-06-19 07:37:33','2026-06-19 07:38:56',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(10,'bdf737af-2032-4473-905c-4b7b66194778',1,'','','',0,2,200,0,'29280f22','2026-06-19 08:17:21','2026-06-19 08:17:21',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(11,'3a6f5dd7-4757-483e-8b96-f5796ee9cd0a',1,'','','',0,2,200,0,'7fbc8058','2026-06-20 14:36:32','2026-06-20 14:36:32',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(12,'5075904f-806c-4716-9bf1-46a0d29118dd',2,'group','','',6,12,200000,0,'d8a80336','2026-06-22 03:15:53','2026-06-28 14:30:52',NULL,0,'',NULL,'',1,1,0,0,0,1,0,'','',0,NULL),(13,'516dacd6-2cca-45b3-a543-bdbee491dbf0',1,'','','',0,2,200,0,'76cf009c','2026-06-22 10:52:46','2026-06-22 10:52:46',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(14,'719a040f-bb34-4716-a43a-5accf9ea43cb',3,'测试1111','','测试11111',21,2,200,1,'d90b6ed6','2026-06-22 10:54:11','2026-06-23 09:04:58',NULL,0,'',NULL,'a11111111',1,1,1,0,0,1,0,'','',0,NULL),(15,'33ddaecd-bd77-470e-8149-57b19dcf246e',1,'','','',0,2,200,0,'257d3619','2026-06-22 10:56:33','2026-06-22 10:56:33',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(16,'a158dc49-b569-4b8e-8913-d5278b654047',1,'','','',0,2,200,0,'27602ad5','2026-06-22 10:56:34','2026-06-22 10:56:34',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(17,'5abe8534-f9eb-4267-933f-1c9e0905f609',1,'','','',0,2,200,0,'1445e3d1','2026-06-22 10:57:02','2026-06-22 10:57:02',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(18,'895a02fe-ae3c-45b8-bed6-de5699f9d084',1,'','','',0,2,200,0,'21bbfae5','2026-06-22 10:57:03','2026-06-22 10:57:03',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(19,'5d55c83d-5ed3-4582-8fa2-1f9cd5be4da9',1,'','','',0,2,200,0,'12f99392','2026-06-22 10:57:30','2026-06-22 10:57:30',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(20,'f6e9962a-a369-4e4c-8abc-cb14d0676ae9',1,'','','',0,2,200,0,'001fa992','2026-06-22 10:57:49','2026-06-22 10:57:49',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(21,'58a53cc1-03fa-417d-9ba7-ebfaf1c3ff3b',1,'','','',0,2,200,0,'594133ba','2026-06-22 10:57:49','2026-06-22 10:57:49',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(22,'a5975aa5-58d8-4e96-9c26-077a63a8edd2',1,'','','',0,2,200,0,'6881e06f','2026-06-22 10:58:18','2026-06-22 10:58:18',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(23,'c7eb842d-09b2-4275-a0e3-1f193d57a644',1,'','','',0,2,200,0,'9c715895','2026-06-22 10:58:18','2026-06-22 10:58:18',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(24,'33d8be82-54d0-4879-bbc0-398202654185',2,'1231231231','','',21,2,200000,1,'caace0da','2026-06-22 10:58:31','2026-06-23 09:03:04',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(25,'ce2d33c3-378c-44f3-9e52-68da1c65f70e',1,'','','',0,2,200,0,'8dd4f9b6','2026-06-22 10:58:57','2026-06-22 10:58:57',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(26,'d868e9ed-a870-4973-9545-217619fa4f24',1,'','','',0,2,200,0,'adc86dbb','2026-06-22 11:03:27','2026-06-22 11:03:27',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(27,'6b524829-ab7a-4b61-ad78-2cf4a867bc42',1,'','','',0,2,200,0,'721fbb1c','2026-06-22 11:06:12','2026-06-22 11:06:12',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(28,'55de3b51-2f10-4f5e-b564-5aac8b155956',1,'','','',0,2,200,0,'87e8bb9f','2026-06-22 11:24:16','2026-06-22 11:24:16',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(29,'83cc991b-4e6c-4309-bdaa-d457200b034c',1,'','','',0,2,200,0,'2559e986','2026-06-23 04:47:56','2026-06-23 04:47:56',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(30,'000d4d6c-096a-4795-b98b-70027aee86fc',1,'','','',0,2,200,0,'28a06037','2026-06-23 04:48:21','2026-06-23 04:48:21',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(31,'dd68e29d-9863-482e-9f08-2b3b47f6fe7c',1,'','','',0,2,200,0,'4a81ba53','2026-06-23 07:55:53','2026-06-23 07:55:53',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(32,'fb4e7886-cf17-48c5-a023-4e1f6abca83b',1,'','','',0,2,200,0,'09af0667','2026-06-23 09:06:49','2026-06-23 09:06:49',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(33,'2b1771f2-02dd-48ea-81da-35b6c5d6f801',2,'123456789','','',28,1,200000,0,'8149e3ea','2026-06-23 09:08:01','2026-06-23 09:08:45',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(34,'a8ed0c2a-a1c5-44b6-888b-d27db4eca569',1,'','','',0,2,200,0,'bb5bb157','2026-06-25 02:13:35','2026-06-25 02:13:35',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(35,'8f5bd114-7d5f-4f9e-a767-f76389d19d67',1,'','','',0,2,200,0,'e5010c77','2026-06-25 02:14:56','2026-06-25 02:14:56',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(36,'8a6c03d2-7ef6-4410-823a-30bb519c9ac6',1,'','','',0,2,200,0,'ac26d130','2026-06-25 02:17:04','2026-06-25 02:17:04',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(37,'a5dc0af5-9fae-4688-a04e-4d827af26a17',1,'','','',0,2,200,0,'2e2d2540','2026-06-25 02:28:18','2026-06-25 02:28:18',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(38,'be7ebf70-8a9f-42cb-b54f-1798835482a3',1,'','','',0,2,200,0,'fd16d4aa','2026-06-25 02:28:18','2026-06-25 02:28:18',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(39,'8010e535-5a99-4849-812e-a6e105720768',1,'','','',0,2,200,0,'28b1aecb','2026-06-25 02:32:44','2026-06-25 02:32:44',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(40,'528216bf-0e0a-4426-bd34-fd4d41031df4',3,'测试频道','','',6,2,200,1,'b80a733c','2026-06-25 14:21:53','2026-06-26 16:51:59',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(41,'78bffd59-9411-402f-8ae3-898cf0e97484',2,'测试','','',25,3,200000,0,'a83b74e3','2026-06-25 14:44:52','2026-06-25 15:07:32',NULL,0,'',NULL,'',1,0,0,0,0,1,0,'a39296f0-bdf5-4c44-8dae-038f98666ef7','http://baidu.com',25,'2026-06-25 15:07:32'),(42,'9ff72db4-e489-4549-9529-d89fc4baadaf',1,'','','',0,2,200,0,'874aa5a4','2026-06-26 14:56:56','2026-06-26 14:56:56',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(43,'8d3c4f35-d3fd-4940-be9a-867b7b803886',1,'','','',0,2,200,0,'1e5ac762','2026-06-27 18:14:51','2026-06-27 18:14:51',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(44,'783d678c-0edc-4a2e-b850-3c361efd22df',1,'','','',0,2,200,0,'6bd75b62','2026-06-27 18:14:58','2026-06-27 18:14:58',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(45,'c64303df-912b-4f1a-a14a-9cb175969f74',1,'','','',0,2,200,0,'d12df1d8','2026-06-28 08:59:39','2026-06-28 08:59:39',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(46,'44903629-91c0-4c41-9531-40f6de2a3865',3,'123','','123',25,1,200,1,'0e28a097','2026-06-28 15:51:59','2026-06-28 15:51:59',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL),(47,'87696741-3ad5-4747-b694-846c7638bad6',2,'123','','',25,2,200000,1,'8f37dc99','2026-06-28 15:52:37','2026-06-28 15:52:37',NULL,0,'',NULL,'',1,1,1,0,0,1,0,'','',0,NULL);
/*!40000 ALTER TABLE `chats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `contacts`
--

DROP TABLE IF EXISTS `contacts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `contacts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `contact_user_id` bigint unsigned NOT NULL,
  `remark` varchar(100) DEFAULT NULL,
  `status` tinyint DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_contact` (`user_id`,`contact_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=115 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `contacts`
--

LOCK TABLES `contacts` WRITE;
/*!40000 ALTER TABLE `contacts` DISABLE KEYS */;
INSERT INTO `contacts` VALUES (1,3,2,'',0,'2026-06-16 15:33:40','2026-06-16 15:33:40'),(2,4,2,'',0,'2026-06-16 15:47:47','2026-06-16 15:47:47'),(5,4,3,'',1,'2026-06-17 02:07:51','2026-06-17 02:08:09'),(6,3,4,'',1,'2026-06-17 02:08:09','2026-06-17 02:08:09'),(7,6,1,'',1,'2026-06-17 14:25:02','2026-06-17 14:26:04'),(8,1,6,'',1,'2026-06-17 14:26:04','2026-06-17 14:26:04'),(9,6,7,'',1,'2026-06-18 06:37:30','2026-06-22 10:56:34'),(10,6,8,'',1,'2026-06-18 06:48:54','2026-06-22 10:57:03'),(11,6,9,'',0,'2026-06-18 06:52:25','2026-06-18 06:52:25'),(12,6,10,'',1,'2026-06-18 06:55:40','2026-06-22 10:57:49'),(13,6,11,'',1,'2026-06-18 06:57:56','2026-06-22 10:58:18'),(14,6,12,'',0,'2026-06-18 06:58:33','2026-06-18 06:58:33'),(15,6,13,'',0,'2026-06-18 07:00:38','2026-06-18 07:00:38'),(16,6,14,'',0,'2026-06-18 07:02:09','2026-06-18 07:02:09'),(17,6,15,'',0,'2026-06-18 07:02:51','2026-06-18 07:02:51'),(36,6,18,'',2,'2026-06-19 08:41:48','2026-06-19 08:41:52'),(37,6,18,'',1,'2026-06-19 10:08:19','2026-06-19 10:08:22'),(38,18,6,'',1,'2026-06-19 10:08:22','2026-06-19 10:08:22'),(39,16,17,'',1,'2026-06-20 14:05:52','2026-06-20 14:07:34'),(40,17,16,'',1,'2026-06-20 14:07:34','2026-06-20 14:07:34'),(41,3,16,'',1,'2026-06-20 14:34:18','2026-06-20 14:36:32'),(42,16,3,'',1,'2026-06-20 14:36:32','2026-06-20 14:36:32'),(43,22,21,'',1,'2026-06-22 10:51:32','2026-06-22 10:52:46'),(44,21,22,'',1,'2026-06-22 10:52:46','2026-06-22 10:52:46'),(45,1,7,'',1,'2026-06-22 10:56:29','2026-06-22 10:56:33'),(46,7,1,'',1,'2026-06-22 10:56:33','2026-06-22 10:56:33'),(47,7,6,'',1,'2026-06-22 10:56:34','2026-06-22 10:56:34'),(48,1,8,'',1,'2026-06-22 10:56:59','2026-06-22 10:57:02'),(49,8,1,'',1,'2026-06-22 10:57:02','2026-06-22 10:57:02'),(50,8,6,'',1,'2026-06-22 10:57:03','2026-06-22 10:57:03'),(51,1,9,'',1,'2026-06-22 10:57:25','2026-06-22 10:57:30'),(52,9,1,'',1,'2026-06-22 10:57:30','2026-06-22 10:57:30'),(53,1,10,'',1,'2026-06-22 10:57:46','2026-06-22 10:57:49'),(54,10,6,'',1,'2026-06-22 10:57:49','2026-06-22 10:57:49'),(55,10,1,'',1,'2026-06-22 10:57:49','2026-06-22 10:57:49'),(56,1,11,'',1,'2026-06-22 10:58:15','2026-06-22 10:58:18'),(57,11,1,'',1,'2026-06-22 10:58:18','2026-06-22 10:58:18'),(58,11,6,'',1,'2026-06-22 10:58:18','2026-06-22 10:58:18'),(59,1,12,'',1,'2026-06-22 10:58:52','2026-06-22 10:58:57'),(60,12,1,'',1,'2026-06-22 10:58:57','2026-06-22 10:58:57'),(61,25,26,'',1,'2026-06-23 04:48:03','2026-06-23 04:48:08'),(62,26,25,'',1,'2026-06-23 04:48:08','2026-06-23 04:48:08'),(63,25,27,'',1,'2026-06-23 04:48:14','2026-06-23 04:48:21'),(64,27,25,'',1,'2026-06-23 04:48:21','2026-06-23 04:48:21'),(65,24,25,'',1,'2026-06-23 07:47:55','2026-06-23 07:47:55'),(66,25,24,'',1,'2026-06-23 07:47:55','2026-06-23 07:47:55'),(67,1,25,'',1,'2026-06-23 07:49:04','2026-06-23 07:49:04'),(68,25,1,'',1,'2026-06-23 07:49:04','2026-06-23 07:49:04'),(69,1,22,'',0,'2026-06-23 07:55:04','2026-06-23 07:55:04'),(70,28,25,'',1,'2026-06-23 08:39:38','2026-06-23 08:39:38'),(71,25,28,'',1,'2026-06-23 08:39:38','2026-06-23 08:39:38'),(72,28,1,'',1,'2026-06-23 08:39:46','2026-06-23 09:06:49'),(73,1,28,'',1,'2026-06-23 09:06:49','2026-06-23 09:06:49'),(74,3,25,'',1,'2026-06-24 00:53:56','2026-06-24 00:53:56'),(75,25,3,'',1,'2026-06-24 00:53:56','2026-06-24 00:53:56'),(76,4,25,'',1,'2026-06-25 01:55:42','2026-06-25 01:55:42'),(77,25,4,'',1,'2026-06-25 01:55:42','2026-06-25 01:55:42'),(78,29,25,'',1,'2026-06-25 02:12:16','2026-06-25 02:12:16'),(79,25,29,'',1,'2026-06-25 02:12:16','2026-06-25 02:12:16'),(80,29,2,'',0,'2026-06-25 02:13:14','2026-06-25 02:13:14'),(81,29,3,'',1,'2026-06-25 02:13:15','2026-06-25 02:14:56'),(82,29,4,'',1,'2026-06-25 02:13:16','2026-06-25 02:13:35'),(83,4,29,'',1,'2026-06-25 02:13:35','2026-06-25 02:13:35'),(84,3,29,'',1,'2026-06-25 02:14:56','2026-06-25 02:14:56'),(85,30,25,'',1,'2026-06-25 02:16:12','2026-06-25 02:16:12'),(86,25,30,'',1,'2026-06-25 02:16:12','2026-06-25 02:16:12'),(87,30,2,'',0,'2026-06-25 02:16:50','2026-06-25 02:16:50'),(88,30,3,'',1,'2026-06-25 02:16:51','2026-06-25 02:28:18'),(89,30,4,'',1,'2026-06-25 02:16:53','2026-06-25 02:17:04'),(90,30,29,'',0,'2026-06-25 02:16:54','2026-06-25 02:16:54'),(91,4,30,'',1,'2026-06-25 02:17:04','2026-06-25 02:17:04'),(92,31,25,'',1,'2026-06-25 02:18:55','2026-06-25 02:18:55'),(93,25,31,'',1,'2026-06-25 02:18:55','2026-06-25 02:18:55'),(94,31,2,'',0,'2026-06-25 02:23:08','2026-06-25 02:23:08'),(95,31,3,'',1,'2026-06-25 02:23:09','2026-06-25 02:28:18'),(96,31,4,'',1,'2026-06-25 02:23:09','2026-06-25 02:32:44'),(97,31,29,'',0,'2026-06-25 02:23:10','2026-06-25 02:23:10'),(98,31,30,'',0,'2026-06-25 02:23:21','2026-06-25 02:23:21'),(99,3,30,'',1,'2026-06-25 02:28:18','2026-06-25 02:28:18'),(100,3,31,'',1,'2026-06-25 02:28:18','2026-06-25 02:28:18'),(101,4,31,'',1,'2026-06-25 02:32:44','2026-06-25 02:32:44'),(102,6,25,'',1,'2026-06-25 14:20:57','2026-06-25 14:20:57'),(103,25,6,'',1,'2026-06-25 14:20:57','2026-06-25 14:20:57'),(104,16,25,'',1,'2026-06-26 21:31:32','2026-06-26 21:31:32'),(105,25,16,'',1,'2026-06-26 21:31:32','2026-06-26 21:31:32'),(106,31,16,'',0,'2026-06-27 18:14:20','2026-06-27 18:14:20'),(107,27,26,'',1,'2026-06-27 22:12:29','2026-06-28 08:59:39'),(108,20,25,'',1,'2026-06-27 23:04:10','2026-06-27 23:04:10'),(109,25,20,'',1,'2026-06-27 23:04:10','2026-06-27 23:04:10'),(110,26,27,'',1,'2026-06-28 08:59:39','2026-06-28 08:59:39'),(111,32,25,'',1,'2026-06-28 14:30:52','2026-06-28 14:30:52'),(112,25,32,'',1,'2026-06-28 14:30:52','2026-06-28 14:30:52'),(113,19,25,'',1,'2026-07-01 10:19:52','2026-07-01 10:19:52'),(114,25,19,'',1,'2026-07-01 10:19:52','2026-07-01 10:19:52');
/*!40000 ALTER TABLE `contacts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `discover_items`
--

DROP TABLE IF EXISTS `discover_items`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `discover_items` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `title` varchar(100) NOT NULL,
  `icon_url` varchar(500) DEFAULT NULL,
  `url` varchar(1000) NOT NULL,
  `sort` bigint DEFAULT '0',
  `enabled` tinyint(1) DEFAULT '1',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_discover_items_sort` (`sort`),
  KEY `idx_discover_items_enabled` (`enabled`),
  KEY `idx_discover_items_created_at` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `discover_items`
--

LOCK TABLES `discover_items` WRITE;
/*!40000 ALTER TABLE `discover_items` DISABLE KEYS */;
INSERT INTO `discover_items` VALUES (1,'测试1111','http://localhost:8081/uploads/discover/2026/06/29/3bfc84a9_1782738946580.png','https://www.bing.com/',0,1,'2026-06-19 06:48:46','2026-06-29 13:15:48'),(2,'测试','http://localhost:8081/uploads/discover/2026/06/29/e6169a6a_1782738963596.jpg','https://www.bing.com/',1,1,'2026-06-29 21:16:06','2026-06-29 13:16:26'),(3,'测试','http://localhost:8081/uploads/discover/2026/06/29/3ddcb517_1782738976326.jpg','https://www.bing.com/',2,1,'2026-06-29 21:16:18','2026-06-29 13:16:28');
/*!40000 ALTER TABLE `discover_items` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `emoji_store_pack_catalogs`
--

DROP TABLE IF EXISTS `emoji_store_pack_catalogs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `emoji_store_pack_catalogs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `pack_id` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL,
  `description` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `preview_emoji` varchar(16) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `preview_file` varchar(100) COLLATE utf8mb4_general_ci NOT NULL,
  `sticker_files` longtext COLLATE utf8mb4_general_ci NOT NULL,
  `sort_order` bigint DEFAULT '0',
  `is_built_in` tinyint(1) DEFAULT '1',
  `is_active` tinyint(1) DEFAULT '1',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_emoji_store_pack_catalogs_pack_id` (`pack_id`),
  KEY `idx_emoji_store_pack_catalogs_sort_order` (`sort_order`),
  KEY `idx_emoji_store_pack_catalogs_is_active` (`is_active`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `emoji_store_pack_catalogs`
--

LOCK TABLES `emoji_store_pack_catalogs` WRITE;
/*!40000 ALTER TABLE `emoji_store_pack_catalogs` DISABLE KEYS */;
INSERT INTO `emoji_store_pack_catalogs` VALUES (1,'animated_faces','动态笑脸','丰富的表情动画','😂','joy.json','[\"joy.json\",\"laughing.json\",\"smiling.json\",\"wink.json\",\"heart_eyes.json\",\"blush.json\",\"yum.json\",\"relieved.json\",\"star_eyes.json\",\"smirk.json\",\"unamused.json\",\"sweat.json\",\"pensive.json\",\"confused.json\",\"confounded.json\",\"kissing.json\",\"kiss.json\",\"kissing_closed.json\",\"stuck_out.json\",\"wink_tongue.json\",\"disappointed.json\",\"worried.json\",\"surprised.json\",\"crying.json\",\"triumph.json\",\"frowning.json\",\"anguished.json\",\"fearful.json\",\"weary.json\",\"sleepy.json\",\"tired.json\",\"grimacing.json\",\"loudly_crying.json\",\"scream.json\",\"astonished.json\",\"flushed.json\",\"angry.json\",\"thinking.json\",\"sunglasses.json\",\"hot.json\",\"cold.json\",\"hug.json\",\"shush.json\",\"vomit.json\",\"sleeping.json\",\"devil.json\",\"angel.json\",\"exploding_head.json\"]',1,1,1,'2026-06-16 15:21:17','2026-06-16 15:21:17'),(2,'animated_animals','动态动物','可爱的动物动画','🐱','cat.json','[\"dog.json\",\"cat.json\",\"pig.json\",\"monkey.json\",\"monkey_face.json\",\"rabbit.json\",\"tiger.json\",\"frog.json\",\"bird.json\",\"hatching_chick.json\",\"baby_chick.json\",\"hatched_chick.json\",\"butterfly.json\",\"bee.json\",\"turtle.json\",\"snake.json\",\"dragon.json\",\"octopus.json\",\"dolphin.json\",\"whale.json\",\"fish.json\",\"unicorn.json\"]',2,1,1,'2026-06-16 15:21:17','2026-06-16 15:21:17'),(3,'animated_nature','动态自然','自然元素动画','🌈','rainbow.json','[\"rainbow.json\",\"snowflake.json\",\"lightning.json\",\"rose.json\",\"four_leaf.json\"]',3,1,1,'2026-06-16 15:21:17','2026-06-16 15:21:17'),(4,'animated_gestures','动态手势','手势表情动画','👍','thumbs_up.json','[\"thumbs_up.json\",\"thumbs_down.json\",\"clap.json\",\"wave.json\",\"ok.json\",\"muscle.json\",\"pray.json\",\"eyes.json\",\"raised_hands.json\",\"point_up.json\",\"point_down.json\",\"point_left.json\",\"point_right.json\",\"fist.json\",\"v_sign.json\",\"call_me.json\",\"love_you.json\"]',4,1,1,'2026-06-16 15:21:17','2026-06-16 15:21:17'),(5,'animated_symbols','动态爱心','爱心和符号动画','❤️','heart.json','[\"heart.json\",\"orange_heart.json\",\"yellow_heart.json\",\"green_heart.json\",\"blue_heart.json\",\"purple_heart.json\",\"broken_heart.json\",\"sparkling_heart.json\",\"heartbeat.json\",\"fire.json\",\"hundred.json\",\"sparkles.json\",\"party.json\",\"tada.json\",\"rocket.json\",\"ghost.json\",\"skull.json\",\"poop.json\"]',5,1,1,'2026-06-16 15:21:17','2026-06-16 15:21:17');
/*!40000 ALTER TABLE `emoji_store_pack_catalogs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `hot_update_patch_reports`
--

DROP TABLE IF EXISTS `hot_update_patch_reports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hot_update_patch_reports` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `patch_id` bigint unsigned NOT NULL DEFAULT '0',
  `patch_ref_id` char(36) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `patch_version` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `platform` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'android',
  `channel` varchar(30) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'stable',
  `delivery_mode` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'self_hosted',
  `app_version` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `build_number` bigint NOT NULL DEFAULT '0',
  `device_id` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `user_uuid` char(36) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` varchar(32) COLLATE utf8mb4_general_ci NOT NULL,
  `message` varchar(500) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `client_ip` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_hot_update_patch_reports_device_id` (`device_id`),
  KEY `idx_hot_update_patch_reports_status` (`status`),
  KEY `idx_hot_update_patch_reports_created_at` (`created_at`),
  KEY `idx_hot_update_patch_reports_channel` (`channel`),
  KEY `idx_hot_update_patch_reports_delivery_mode` (`delivery_mode`),
  KEY `idx_hot_update_patch_reports_user_uuid` (`user_uuid`),
  KEY `idx_hot_update_patch_reports_patch_id` (`patch_id`),
  KEY `idx_hot_update_patch_reports_patch_ref_id` (`patch_ref_id`),
  KEY `idx_hot_update_patch_reports_platform` (`platform`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `hot_update_patch_reports`
--

LOCK TABLES `hot_update_patch_reports` WRITE;
/*!40000 ALTER TABLE `hot_update_patch_reports` DISABLE KEYS */;
/*!40000 ALTER TABLE `hot_update_patch_reports` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `hot_update_patches`
--

DROP TABLE IF EXISTS `hot_update_patches`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `hot_update_patches` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `patch_id` char(36) COLLATE utf8mb4_general_ci NOT NULL,
  `name` varchar(120) COLLATE utf8mb4_general_ci NOT NULL,
  `description` varchar(500) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `platform` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'android',
  `channel` varchar(30) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'stable',
  `delivery_mode` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'self_hosted',
  `min_app_version` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `max_app_version` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `min_build_number` bigint NOT NULL DEFAULT '0',
  `max_build_number` bigint NOT NULL DEFAULT '0',
  `target_app_version` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `patch_version` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `patch_url` varchar(500) COLLATE utf8mb4_general_ci NOT NULL,
  `patch_hash` varchar(128) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `release_notes` text COLLATE utf8mb4_general_ci,
  `rollout_percentage` bigint NOT NULL DEFAULT '100',
  `is_mandatory` tinyint(1) NOT NULL DEFAULT '0',
  `priority` bigint NOT NULL DEFAULT '0',
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'draft',
  `start_at` datetime(3) DEFAULT NULL,
  `end_at` datetime(3) DEFAULT NULL,
  `published_at` datetime(3) DEFAULT NULL,
  `paused_at` datetime(3) DEFAULT NULL,
  `rollback_at` datetime(3) DEFAULT NULL,
  `created_by` bigint unsigned DEFAULT NULL,
  `updated_by` bigint unsigned DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_hot_update_patches_patch_id` (`patch_id`),
  KEY `idx_hot_update_patches_delivery_mode` (`delivery_mode`),
  KEY `idx_hot_update_patches_priority` (`priority`),
  KEY `idx_hot_update_patches_end_at` (`end_at`),
  KEY `idx_hot_update_patches_platform` (`platform`),
  KEY `idx_hot_update_patches_rollout_percentage` (`rollout_percentage`),
  KEY `idx_hot_update_patches_status` (`status`),
  KEY `idx_hot_update_patches_start_at` (`start_at`),
  KEY `idx_hot_update_patches_deleted_at` (`deleted_at`),
  KEY `idx_hot_update_patches_channel` (`channel`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `hot_update_patches`
--

LOCK TABLES `hot_update_patches` WRITE;
/*!40000 ALTER TABLE `hot_update_patches` DISABLE KEYS */;
/*!40000 ALTER TABLE `hot_update_patches` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `invite_code_usages`
--

DROP TABLE IF EXISTS `invite_code_usages`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `invite_code_usages` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `invite_code_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_invite_code_usages_invite_code_id` (`invite_code_id`),
  KEY `idx_invite_code_usages_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `invite_code_usages`
--

LOCK TABLES `invite_code_usages` WRITE;
/*!40000 ALTER TABLE `invite_code_usages` DISABLE KEYS */;
/*!40000 ALTER TABLE `invite_code_usages` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `invite_codes`
--

DROP TABLE IF EXISTS `invite_codes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `invite_codes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `code` varchar(32) COLLATE utf8mb4_general_ci NOT NULL,
  `service_user_id` bigint unsigned NOT NULL,
  `service_user_uuid` char(36) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `max_uses` bigint DEFAULT '0',
  `used_count` bigint DEFAULT '0',
  `status` tinyint DEFAULT '1',
  `remark` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `expires_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_invite_codes_code` (`code`),
  KEY `idx_invite_codes_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `invite_codes`
--

LOCK TABLES `invite_codes` WRITE;
/*!40000 ALTER TABLE `invite_codes` DISABLE KEYS */;
INSERT INTO `invite_codes` VALUES (1,'123456',25,'fc387b56-6781-46b9-80ad-026075cd0a89',0,0,1,'官方客服专属邀请码',NULL,'2026-06-23 06:38:19','2026-06-23 06:38:19',NULL);
/*!40000 ALTER TABLE `invite_codes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `join_requests`
--

DROP TABLE IF EXISTS `join_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `join_requests` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `chat_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `message` varchar(500) DEFAULT NULL,
  `status` tinyint DEFAULT '0',
  `reviewer_id` bigint unsigned DEFAULT '0',
  `reviewed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_join_requests_chat_id` (`chat_id`),
  KEY `idx_join_requests_user_id` (`user_id`),
  KEY `idx_join_requests_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `join_requests`
--

LOCK TABLES `join_requests` WRITE;
/*!40000 ALTER TABLE `join_requests` DISABLE KEYS */;
/*!40000 ALTER TABLE `join_requests` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `meeting_invites`
--

DROP TABLE IF EXISTS `meeting_invites`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `meeting_invites` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `meeting_id` bigint unsigned NOT NULL,
  `inviter_id` bigint unsigned NOT NULL,
  `invitee_id` bigint unsigned NOT NULL,
  `invite_type` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'invite',
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `responded_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_meeting_invitee` (`meeting_id`,`invitee_id`),
  KEY `idx_meeting_invites_inviter_id` (`inviter_id`),
  KEY `idx_meeting_invites_invite_type` (`invite_type`),
  KEY `idx_meeting_invites_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `meeting_invites`
--

LOCK TABLES `meeting_invites` WRITE;
/*!40000 ALTER TABLE `meeting_invites` DISABLE KEYS */;
/*!40000 ALTER TABLE `meeting_invites` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `meeting_participants`
--

DROP TABLE IF EXISTS `meeting_participants`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `meeting_participants` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `meeting_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `role` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'member',
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'invited',
  `inviter_id` bigint unsigned DEFAULT '0',
  `joined_at` datetime DEFAULT NULL,
  `left_at` datetime DEFAULT NULL,
  `muted_audio` tinyint(1) NOT NULL DEFAULT '0',
  `muted_video` tinyint(1) NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_meeting_user` (`meeting_id`,`user_id`),
  KEY `idx_meeting_participants_inviter_id` (`inviter_id`),
  KEY `idx_meeting_participants_meeting_id` (`meeting_id`),
  KEY `idx_meeting_participants_user_id` (`user_id`),
  KEY `idx_meeting_participants_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `meeting_participants`
--

LOCK TABLES `meeting_participants` WRITE;
/*!40000 ALTER TABLE `meeting_participants` DISABLE KEYS */;
/*!40000 ALTER TABLE `meeting_participants` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `meetings`
--

DROP TABLE IF EXISTS `meetings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `meetings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` char(36) COLLATE utf8mb4_general_ci NOT NULL,
  `channel_name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL,
  `chat_id` bigint unsigned DEFAULT '0',
  `creator_id` bigint unsigned NOT NULL,
  `title` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `meeting_type` varchar(20) COLLATE utf8mb4_general_ci NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'active',
  `max_participants` bigint NOT NULL DEFAULT '16',
  `start_time` datetime NOT NULL,
  `end_time` datetime DEFAULT NULL,
  `duration` bigint NOT NULL DEFAULT '0',
  `end_reason` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_meetings_uuid` (`uuid`),
  UNIQUE KEY `idx_meetings_channel_name` (`channel_name`),
  KEY `idx_meetings_status` (`status`),
  KEY `idx_meetings_chat_id` (`chat_id`),
  KEY `idx_meetings_creator_id` (`creator_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `meetings`
--

LOCK TABLES `meetings` WRITE;
/*!40000 ALTER TABLE `meetings` DISABLE KEYS */;
/*!40000 ALTER TABLE `meetings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `membership_orders`
--

DROP TABLE IF EXISTS `membership_orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `membership_orders` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `order_no` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `plan_id` bigint unsigned NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `pay_channel` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'wallet',
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `remark` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `paid_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_membership_orders_order_no` (`order_no`),
  KEY `idx_membership_orders_created_at` (`created_at`),
  KEY `idx_membership_orders_user_id` (`user_id`),
  KEY `idx_membership_orders_plan_id` (`plan_id`),
  KEY `idx_membership_orders_status` (`status`),
  CONSTRAINT `fk_membership_orders_plan` FOREIGN KEY (`plan_id`) REFERENCES `membership_plans` (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `membership_orders`
--

LOCK TABLES `membership_orders` WRITE;
/*!40000 ALTER TABLE `membership_orders` DISABLE KEYS */;
/*!40000 ALTER TABLE `membership_orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `membership_plans`
--

DROP TABLE IF EXISTS `membership_plans`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `membership_plans` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL,
  `slug` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `duration_days` bigint NOT NULL,
  `price` decimal(12,2) NOT NULL,
  `original_price` decimal(12,2) DEFAULT '0.00',
  `badge_label` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `badge_color` varchar(20) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `description` varchar(300) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `features` text COLLATE utf8mb4_general_ci,
  `status` tinyint DEFAULT '1',
  `sort` bigint DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_membership_plans_slug` (`slug`),
  KEY `idx_membership_plans_status` (`status`),
  KEY `idx_membership_plans_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `membership_plans`
--

LOCK TABLES `membership_plans` WRITE;
/*!40000 ALTER TABLE `membership_plans` DISABLE KEYS */;
INSERT INTO `membership_plans` VALUES (1,'月度会员','monthly',30,28.00,38.00,'PREMIUM','#3390EC','适合先体验高级功能的用户','[\"会员徽章\",\"更高上传限制\",\"高级贴纸权限\",\"更多会话置顶\"]',1,1,'2026-06-16 05:52:59','2026-06-16 05:52:59',NULL),(2,'季度会员','quarterly',90,78.00,114.00,'PREMIUM','#8B5CF6','性价比更高，适合稳定使用','[\"会员徽章\",\"更高上传限制\",\"高级贴纸权限\",\"更多会话置顶\"]',1,2,'2026-06-16 05:52:59','2026-06-16 05:52:59',NULL),(3,'年度会员','yearly',365,298.00,456.00,'PREMIUM','#F59E0B','最划算，适合长期使用','[\"会员徽章\",\"更高上传限制\",\"高级贴纸权限\",\"更多会话置顶\"]',1,3,'2026-06-16 05:52:59','2026-06-16 05:52:59',NULL);
/*!40000 ALTER TABLE `membership_plans` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `moment_blocks`
--

DROP TABLE IF EXISTS `moment_blocks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `moment_blocks` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL,
  `moment_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_moment` (`user_id`,`moment_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `moment_blocks`
--

LOCK TABLES `moment_blocks` WRITE;
/*!40000 ALTER TABLE `moment_blocks` DISABLE KEYS */;
/*!40000 ALTER TABLE `moment_blocks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `moment_comments`
--

DROP TABLE IF EXISTS `moment_comments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `moment_comments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(36) DEFAULT NULL,
  `moment_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `parent_id` bigint unsigned DEFAULT NULL,
  `reply_to_id` bigint unsigned DEFAULT NULL,
  `content` text NOT NULL,
  `like_count` bigint DEFAULT '0',
  `status` tinyint DEFAULT '1',
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_moment_comments_uuid` (`uuid`),
  KEY `idx_moment_comments_reply_to_id` (`reply_to_id`),
  KEY `idx_moment_comments_deleted_at` (`deleted_at`),
  KEY `idx_moment_comments_moment_id` (`moment_id`),
  KEY `idx_moment_comments_user_id` (`user_id`),
  KEY `idx_moment_comments_parent_id` (`parent_id`),
  CONSTRAINT `fk_moment_comments_moment` FOREIGN KEY (`moment_id`) REFERENCES `moments` (`id`),
  CONSTRAINT `fk_moment_comments_replies` FOREIGN KEY (`parent_id`) REFERENCES `moment_comments` (`id`),
  CONSTRAINT `fk_moment_comments_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `moment_comments`
--

LOCK TABLES `moment_comments` WRITE;
/*!40000 ALTER TABLE `moment_comments` DISABLE KEYS */;
INSERT INTO `moment_comments` VALUES (1,'b733f3ee-ae09-49f2-8f8d-8c6ee0875fb2',8,4,NULL,NULL,'666',0,1,'2026-06-16 16:17:02.361','2026-06-16 16:17:02.361',NULL),(2,'53cafd20-00e5-4138-ae0a-165da48aaff9',5,3,NULL,NULL,'莫',0,1,'2026-06-16 16:17:06.189','2026-06-16 16:17:06.189',NULL),(3,'2ac11d4d-6f9d-4af5-a847-e10c7bdda5a1',14,16,NULL,NULL,'123123',0,1,'2026-06-19 06:05:20.038','2026-06-19 06:05:20.038',NULL);
/*!40000 ALTER TABLE `moment_comments` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `moment_likes`
--

DROP TABLE IF EXISTS `moment_likes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `moment_likes` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `moment_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `created_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_moment_likes_moment_id` (`moment_id`),
  KEY `idx_moment_likes_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=7 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `moment_likes`
--

LOCK TABLES `moment_likes` WRITE;
/*!40000 ALTER TABLE `moment_likes` DISABLE KEYS */;
INSERT INTO `moment_likes` VALUES (1,8,4,'2026-06-16 16:16:40.994'),(2,5,3,'2026-06-16 16:16:56.624'),(3,10,1,'2026-06-18 04:02:15.256'),(4,11,6,'2026-06-18 04:02:45.040'),(5,14,17,'2026-06-19 06:06:54.666'),(6,14,16,'2026-06-19 06:07:01.310');
/*!40000 ALTER TABLE `moment_likes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `moments`
--

DROP TABLE IF EXISTS `moments`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `moments` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(36) DEFAULT NULL,
  `user_id` bigint unsigned DEFAULT NULL,
  `content` text,
  `content_type` tinyint DEFAULT '1',
  `media_urls` json DEFAULT NULL,
  `video_thumbnail` varchar(500) DEFAULT NULL,
  `topics` json DEFAULT NULL,
  `visibility` tinyint DEFAULT '1',
  `selected_contacts` json DEFAULT NULL,
  `like_count` bigint DEFAULT '0',
  `comment_count` bigint DEFAULT '0',
  `share_count` bigint DEFAULT '0',
  `view_count` bigint DEFAULT '0',
  `status` tinyint DEFAULT NULL,
  `location` varchar(200) DEFAULT NULL,
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `review_reason` varchar(500) DEFAULT NULL,
  `reviewed_by` bigint unsigned DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_moments_uuid` (`uuid`),
  KEY `idx_moments_user_id` (`user_id`),
  KEY `idx_moments_deleted_at` (`deleted_at`),
  KEY `idx_moments_reviewed_by` (`reviewed_by`),
  CONSTRAINT `fk_moments_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `moments`
--

LOCK TABLES `moments` WRITE;
/*!40000 ALTER TABLE `moments` DISABLE KEYS */;
INSERT INTO `moments` VALUES (1,'ff8a1530-8016-4c74-87d8-753c0f8d94dc',2,'😂',1,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-16 15:21:24.233','2026-06-16 15:21:24.233',NULL,NULL,NULL,NULL),(2,'5f9e4782-978b-4030-b714-b00bc42b7c76',2,'666',2,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-16 15:21:44.631','2026-06-16 15:21:44.631',NULL,NULL,NULL,NULL),(3,'2c3b99da-6cd6-4245-b090-151f432a159e',2,'555\n',2,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-16 15:22:07.394','2026-06-16 15:22:07.394',NULL,NULL,NULL,NULL),(4,'da98a03c-dab6-47e0-862c-9db325b2d7e5',2,'',2,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-16 15:22:30.252','2026-06-16 15:22:30.252',NULL,NULL,NULL,NULL),(5,'7c4a9674-15fa-4772-b76c-4faaebb86a15',3,'你**',1,'[]','','[]',4,'null',1,1,0,0,1,'','2026-06-16 16:13:52.968','2026-06-16 16:17:59.939',NULL,'',NULL,NULL),(6,'b1dd510c-cfd2-40f8-8ee6-e465d7c91ecd',3,'日了狗了',1,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-16 16:14:37.753','2026-06-16 16:14:37.753',NULL,NULL,NULL,NULL),(7,'a0872e0d-6f01-4c85-b4fc-1d6b53838760',3,'日了个狗🐶',1,'[]','','[]',4,'null',0,0,0,0,3,'','2026-06-16 16:15:10.396','2026-06-16 16:19:46.563',NULL,'',NULL,NULL),(8,'802bde15-f723-4976-bbd7-5a306af5e016',4,'2222',1,'[]','','[]',1,'null',1,1,0,0,1,'','2026-06-16 16:15:45.004','2026-06-16 16:15:45.004',NULL,NULL,NULL,NULL),(9,'42a9ba78-0248-4d48-9eca-fff93132de4b',1,'test',2,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-17 12:58:08.157','2026-06-17 12:58:08.157',NULL,NULL,NULL,NULL),(10,'e4851c09-3fd9-4659-a806-f17ce4553de8',1,'123123',2,'[]','','[]',1,'null',1,0,0,0,1,'','2026-06-17 12:59:21.209','2026-06-17 12:59:21.209',NULL,NULL,NULL,NULL),(11,'bcb368da-3daf-404f-9ac9-ccfaec552409',1,'test',2,'[\"http://localhost:8081/uploads/images/2026/06/18/4256d3f8_1781755120731.jpeg\"]','','[]',1,'null',1,0,0,0,1,'','2026-06-18 03:58:41.240','2026-06-18 03:58:41.240',NULL,NULL,NULL,NULL),(12,'1abab3b9-c515-42a3-881a-39a19aec5212',6,'123',1,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-18 04:00:31.799','2026-06-18 04:00:31.799',NULL,NULL,NULL,NULL),(13,'4cab67e3-506e-4c51-82c6-4847d1b37638',6,'123',1,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-18 04:00:33.196','2026-06-18 04:00:33.196',NULL,NULL,NULL,NULL),(14,'d3a405e0-ba77-4aa7-96d0-f1dd0a356ba8',17,'1123123213123',1,'[]','','[]',1,'null',2,1,0,0,1,'','2026-06-19 06:05:12.308','2026-06-19 06:05:12.308',NULL,NULL,NULL,NULL),(15,'e737a929-0eaf-40f4-ac01-ae8dd89065f2',17,'4444444444444444444',1,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-19 06:30:04.877','2026-06-19 06:30:04.877',NULL,NULL,NULL,NULL),(16,'713087e2-9183-4bcf-a13c-b2ec2c64e680',25,'123',1,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-23 06:45:57.668','2026-06-23 06:46:06.980',NULL,'',1,'2026-06-23 06:46:07'),(17,'95ad9ba4-a5a3-4ad8-84c5-0338621b9b1a',3,'8080=',1,'[]','','[]',1,'null',0,0,0,0,0,'','2026-06-24 16:15:00.596','2026-06-24 16:15:00.596',NULL,NULL,NULL,NULL),(18,'29946dfc-603f-421b-a6ba-c5412768e349',1,'test',1,'[]','','[]',1,'null',0,0,0,0,1,'','2026-06-25 13:07:01.872','2026-06-25 13:07:18.630',NULL,'',1,'2026-06-25 13:07:19');
/*!40000 ALTER TABLE `moments` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `official_channels`
--

DROP TABLE IF EXISTS `official_channels`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `official_channels` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `chat_id` bigint unsigned NOT NULL,
  `chat_uuid` char(36) NOT NULL,
  `remark` varchar(200) DEFAULT NULL,
  `sort_order` bigint DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_official_channels_chat_id` (`chat_id`),
  UNIQUE KEY `idx_official_channels_chat_uuid` (`chat_uuid`),
  KEY `idx_official_channels_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `official_channels`
--

LOCK TABLES `official_channels` WRITE;
/*!40000 ALTER TABLE `official_channels` DISABLE KEYS */;
/*!40000 ALTER TABLE `official_channels` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `official_groups`
--

DROP TABLE IF EXISTS `official_groups`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `official_groups` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `chat_id` bigint unsigned NOT NULL,
  `chat_uuid` char(36) NOT NULL,
  `remark` varchar(200) DEFAULT NULL,
  `sort_order` bigint DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_official_groups_chat_uuid` (`chat_uuid`),
  UNIQUE KEY `idx_official_groups_chat_id` (`chat_id`),
  KEY `idx_official_groups_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `official_groups`
--

LOCK TABLES `official_groups` WRITE;
/*!40000 ALTER TABLE `official_groups` DISABLE KEYS */;
INSERT INTO `official_groups` VALUES (1,12,'5075904f-806c-4716-9bf1-46a0d29118dd','',0,'2026-06-22 11:21:42','2026-06-22 11:21:42',NULL);
/*!40000 ALTER TABLE `official_groups` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `official_users`
--

DROP TABLE IF EXISTS `official_users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `official_users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `user_uuid` char(36) NOT NULL,
  `remark` varchar(200) DEFAULT NULL,
  `sort_order` bigint DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `welcome_message` varchar(500) DEFAULT NULL,
  `is_service_enabled` tinyint(1) DEFAULT '1',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_official_users_user_id` (`user_id`),
  UNIQUE KEY `idx_official_users_user_uuid` (`user_uuid`),
  KEY `idx_official_users_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `official_users`
--

LOCK TABLES `official_users` WRITE;
/*!40000 ALTER TABLE `official_users` DISABLE KEYS */;
INSERT INTO `official_users` VALUES (1,25,'fc387b56-6781-46b9-80ad-026075cd0a89','',0,'2026-06-23 06:38:19','2026-06-23 06:38:19',NULL,'欢迎参加测试',1);
/*!40000 ALTER TABLE `official_users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `popup_announcements`
--

DROP TABLE IF EXISTS `popup_announcements`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `popup_announcements` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `title` varchar(200) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '',
  `content` text COLLATE utf8mb4_general_ci NOT NULL,
  `image_url` varchar(500) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '',
  `link_url` varchar(500) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '',
  `enabled` tinyint NOT NULL DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_popup_announcements_enabled` (`enabled`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `popup_announcements`
--

LOCK TABLES `popup_announcements` WRITE;
/*!40000 ALTER TABLE `popup_announcements` DISABLE KEYS */;
INSERT INTO `popup_announcements` VALUES (1,'222','222','','',1,'2026-06-16 16:11:35','2026-06-16 16:11:35');
/*!40000 ALTER TABLE `popup_announcements` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `push_delivery_logs`
--

DROP TABLE IF EXISTS `push_delivery_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `push_delivery_logs` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `device_id` bigint unsigned NOT NULL,
  `device_key` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `channel` varchar(20) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `success` tinyint(1) NOT NULL DEFAULT '0',
  `error` varchar(512) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `title` varchar(120) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `body` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `occurred_at` datetime NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_push_delivery_logs_user_id` (`user_id`),
  KEY `idx_push_delivery_logs_device_id` (`device_id`),
  KEY `idx_push_delivery_logs_device_key` (`device_key`),
  KEY `idx_push_delivery_logs_channel` (`channel`),
  KEY `idx_push_delivery_logs_success` (`success`),
  KEY `idx_push_delivery_logs_occurred_at` (`occurred_at`)
) ENGINE=InnoDB AUTO_INCREMENT=117 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `push_delivery_logs`
--

LOCK TABLES `push_delivery_logs` WRITE;
/*!40000 ALTER TABLE `push_delivery_logs` DISABLE KEYS */;
INSERT INTO `push_delivery_logs` VALUES (1,2,2,'d6bbcfb0-9a49-4dcd-981b-efbb76f66712','fcm',0,'Android 推送通道未启用: fcm','推送诊断','这是一条后台测试推送，用于验证当前设备推送通道。','2026-06-16 15:26:02','2026-06-16 15:26:02'),(2,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','666','2026-06-16 15:52:11','2026-06-16 15:52:11'),(3,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','bb2a59bf','2026-06-17 02:05:53','2026-06-17 02:05:53'),(4,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','223','2026-06-17 02:08:34','2026-06-17 02:08:34'),(5,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','5556','2026-06-17 02:08:51','2026-06-17 02:08:51'),(6,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','777','2026-06-17 02:09:05','2026-06-17 02:09:05'),(7,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','235','2026-06-17 02:09:48','2026-06-17 02:09:48'),(8,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','123123','2026-06-20 14:36:51','2026-06-20 14:36:51'),(9,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','12312313','2026-06-20 14:36:51','2026-06-20 14:36:51'),(10,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','12','2026-06-20 14:36:51','2026-06-20 14:36:51'),(11,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','3','2026-06-20 14:36:51','2026-06-20 14:36:51'),(12,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','123213','2026-06-20 14:36:52','2026-06-20 14:36:52'),(13,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','123','2026-06-20 14:36:52','2026-06-20 14:36:52'),(14,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','123','2026-06-20 14:36:53','2026-06-20 14:36:53'),(15,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','12312','2026-06-20 14:36:53','2026-06-20 14:36:53'),(16,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','3213','2026-06-20 14:36:54','2026-06-20 14:36:54'),(17,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','123213123','2026-06-20 14:36:57','2026-06-20 14:36:57'),(18,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','1999999测试','21312312','2026-06-20 14:36:58','2026-06-20 14:36:58'),(19,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','2','2026-06-21 14:15:07','2026-06-21 14:15:07'),(20,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','3','2026-06-21 14:15:10','2026-06-21 14:15:10'),(21,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','4','2026-06-21 14:16:31','2026-06-21 14:16:31'),(22,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','5','2026-06-21 14:16:36','2026-06-21 14:16:36'),(23,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','11','2026-06-22 02:16:53','2026-06-22 02:16:53'),(24,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','22','2026-06-22 02:17:45','2026-06-22 02:17:45'),(25,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','333','2026-06-22 02:35:07','2026-06-22 02:35:07'),(26,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','444','2026-06-22 02:50:19','2026-06-22 02:50:19'),(27,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','22','2026-06-22 06:38:16','2026-06-22 06:38:16'),(28,16,38,'7349e193-76fa-4651-a5ae-0ce8dbcd6a15','fcm',0,'Android 推送通道未启用: fcm','188测试','111111111','2026-06-22 09:18:04','2026-06-22 09:18:04'),(29,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','33','2026-06-22 10:35:17','2026-06-22 10:35:17'),(30,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','222','44','2026-06-22 10:36:10','2026-06-22 10:36:10'),(31,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','测试22222','111','2026-06-22 11:04:41','2026-06-22 11:04:41'),(32,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','测试22222','22','2026-06-22 11:04:42','2026-06-22 11:04:42'),(33,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','测试22222','测试1111','2026-06-22 11:04:56','2026-06-22 11:04:56'),(34,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','测试22222','频道','2026-06-22 11:04:57','2026-06-22 11:04:57'),(35,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','测试1111','324234234','2026-06-22 11:11:36','2026-06-22 11:11:36'),(36,16,38,'7349e193-76fa-4651-a5ae-0ce8dbcd6a15','fcm',0,'Android 推送通道未启用: fcm','看看','11','2026-06-22 14:25:28','2026-06-22 14:25:28'),(37,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','推送诊断','这是一条后台测试推送，用于验证当前设备推送通道。','2026-06-23 04:39:44','2026-06-23 04:39:44'),(38,26,61,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi','1','2026-06-23 04:47:59','2026-06-23 04:47:59'),(39,16,38,'7349e193-76fa-4651-a5ae-0ce8dbcd6a15','fcm',0,'Android 推送通道未启用: fcm','看看','[图片]','2026-06-24 00:57:32','2026-06-24 00:57:32'),(40,16,38,'7349e193-76fa-4651-a5ae-0ce8dbcd6a15','fcm',0,'Android 推送通道未启用: fcm','看看','你好','2026-06-24 00:57:37','2026-06-24 00:57:37'),(41,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','222','2026-06-25 01:58:37','2026-06-25 01:58:37'),(42,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','23','2026-06-25 02:03:40','2026-06-25 02:03:40'),(43,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','232','2026-06-25 02:03:53','2026-06-25 02:03:53'),(44,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','366','2026-06-25 02:04:43','2026-06-25 02:04:43'),(45,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','23235','2026-06-25 02:04:44','2026-06-25 02:04:44'),(46,3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','15','2026-06-25 02:04:45','2026-06-25 02:04:45'),(47,16,38,'7349e193-76fa-4651-a5ae-0ce8dbcd6a15','fcm',0,'Android 推送通道未启用: fcm','看看','111','2026-06-25 02:09:12','2026-06-25 02:09:12'),(48,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi2','1','2026-06-25 14:24:20','2026-06-25 14:24:20'),(49,6,43,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','fcm',0,'Android 推送通道未启用: fcm','11122','测试频道','2026-06-26 16:51:38','2026-06-26 16:51:38'),(50,6,30,'54efaf71-2d66-4682-8124-41cf31d258be','fcm',0,'Android 推送通道未启用: fcm','11122','测试频道','2026-06-26 16:51:38','2026-06-26 16:51:38'),(51,1,29,'7169774a-7e6f-4a22-a489-895d8296d332','fcm',0,'Android 推送通道未启用: fcm','22222222222','www.google.com','2026-06-27 14:18:54','2026-06-27 14:18:54'),(52,6,30,'54efaf71-2d66-4682-8124-41cf31d258be','fcm',0,'Android 推送通道未启用: fcm','11122','123','2026-06-27 14:19:32','2026-06-27 14:19:32'),(53,6,43,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','fcm',0,'Android 推送通道未启用: fcm','11122','123','2026-06-27 14:19:32','2026-06-27 14:19:32'),(54,16,38,'7349e193-76fa-4651-a5ae-0ce8dbcd6a15','fcm',0,'Android 推送通道未启用: fcm','4444','来电: 视频通话','2026-06-27 18:14:25','2026-06-27 18:14:25'),(55,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','4444','是','2026-06-27 18:15:03','2026-06-27 18:15:03'),(56,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','4444','是','2026-06-27 18:15:03','2026-06-27 18:15:03'),(57,31,66,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','来电: 语音通话','2026-06-27 20:16:15','2026-06-27 20:16:15'),(58,31,66,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','来电: 视频通话','2026-06-27 20:16:39','2026-06-27 20:16:39'),(59,31,66,'7eaea88a-46cd-4ec4-8860-15c699077900','fcm',0,'Android 推送通道未启用: fcm','002','来电: 视频通话','2026-06-27 20:17:16','2026-06-27 20:17:16'),(60,3,71,'e82a5b03-c1e1-4e8f-9190-40451df7cde4','fcm',0,'Android 推送通道未启用: fcm','4444','来电: 视频通话','2026-06-27 20:28:28','2026-06-27 20:28:28'),(61,3,71,'e82a5b03-c1e1-4e8f-9190-40451df7cde4','fcm',0,'Android 推送通道未启用: fcm','4444','来电: 语音通话','2026-06-27 20:29:10','2026-06-27 20:29:10'),(62,3,71,'e82a5b03-c1e1-4e8f-9190-40451df7cde4','fcm',0,'Android 推送通道未启用: fcm','4444','来电: 视频通话','2026-06-27 20:29:41','2026-06-27 20:29:41'),(63,3,71,'e82a5b03-c1e1-4e8f-9190-40451df7cde4','fcm',0,'Android 推送通道未启用: fcm','4444','来电: 语音通话','2026-06-27 20:49:42','2026-06-27 20:49:42'),(64,3,71,'e82a5b03-c1e1-4e8f-9190-40451df7cde4','fcm',0,'Android 推送通道未启用: fcm','4444','来电: 视频通话','2026-06-27 20:49:49','2026-06-27 20:49:49'),(65,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi2','在吗','2026-06-27 21:39:01','2026-06-27 21:39:01'),(66,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi2','在吗','2026-06-27 21:39:01','2026-06-27 21:39:01'),(67,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi2','在吗','2026-06-27 21:39:01','2026-06-27 21:39:01'),(68,26,61,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','测试客服','在','2026-06-27 21:39:26','2026-06-27 21:39:26'),(69,26,73,'1f707afa-7ffa-4031-886b-549751113ea9','fcm',0,'Android 推送通道未启用: fcm','测试客服','在','2026-06-27 21:39:26','2026-06-27 21:39:26'),(70,26,73,'1f707afa-7ffa-4031-886b-549751113ea9','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 语音通话','2026-06-27 21:39:30','2026-06-27 21:39:30'),(71,26,61,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 语音通话','2026-06-27 21:39:30','2026-06-27 21:39:30'),(72,26,61,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 视频通话','2026-06-27 21:40:43','2026-06-27 21:40:43'),(73,26,73,'1f707afa-7ffa-4031-886b-549751113ea9','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 视频通话','2026-06-27 21:40:43','2026-06-27 21:40:43'),(74,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-27 22:12:57','2026-06-27 22:12:57'),(75,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-27 22:12:57','2026-06-27 22:12:57'),(76,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-27 22:12:57','2026-06-27 22:12:57'),(77,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[语音]','2026-06-27 22:13:18','2026-06-27 22:13:18'),(78,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[语音]','2026-06-27 22:13:18','2026-06-27 22:13:18'),(79,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[语音]','2026-06-27 22:13:18','2026-06-27 22:13:18'),(80,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-28 08:48:17','2026-06-28 08:48:17'),(81,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-28 08:48:17','2026-06-28 08:48:17'),(82,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-28 08:48:17','2026-06-28 08:48:17'),(83,26,73,'1f707afa-7ffa-4031-886b-549751113ea9','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 语音通话','2026-06-28 08:48:32','2026-06-28 08:48:32'),(84,26,61,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 语音通话','2026-06-28 08:48:32','2026-06-28 08:48:32'),(85,26,61,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 视频通话','2026-06-28 08:49:04','2026-06-28 08:49:04'),(86,26,73,'1f707afa-7ffa-4031-886b-549751113ea9','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 视频通话','2026-06-28 08:49:04','2026-06-28 08:49:04'),(87,27,62,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 语音通话','2026-06-28 08:49:18','2026-06-28 08:49:18'),(88,27,74,'2752a3e0-5c33-4036-b181-50e19dbf1968','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 语音通话','2026-06-28 08:49:18','2026-06-28 08:49:18'),(89,27,75,'35f52136-08aa-4b20-ac3c-9403396b62bb','fcm',0,'Android 推送通道未启用: fcm','测试客服','来电: 语音通话','2026-06-28 08:49:18','2026-06-28 08:49:18'),(90,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','哈喽😃','2026-06-28 08:54:47','2026-06-28 08:54:47'),(91,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','哈喽😃','2026-06-28 08:54:47','2026-06-28 08:54:47'),(92,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','哈喽😃','2026-06-28 08:54:47','2026-06-28 08:54:47'),(93,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','😉','2026-06-28 08:54:51','2026-06-28 08:54:51'),(94,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','😉','2026-06-28 08:54:51','2026-06-28 08:54:51'),(95,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','😉','2026-06-28 08:54:51','2026-06-28 08:54:51'),(96,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','😉','2026-06-28 08:54:51','2026-06-28 08:54:51'),(97,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','😉','2026-06-28 08:54:51','2026-06-28 08:54:51'),(98,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','😉','2026-06-28 08:54:51','2026-06-28 08:54:51'),(99,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[图片]','2026-06-28 08:55:49','2026-06-28 08:55:49'),(100,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[图片]','2026-06-28 08:55:49','2026-06-28 08:55:49'),(101,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[图片]','2026-06-28 08:55:49','2026-06-28 08:55:49'),(102,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[视频]','2026-06-28 08:56:07','2026-06-28 08:56:07'),(103,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[视频]','2026-06-28 08:56:07','2026-06-28 08:56:07'),(104,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[视频]','2026-06-28 08:56:07','2026-06-28 08:56:07'),(105,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[语音]','2026-06-28 08:56:19','2026-06-28 08:56:19'),(106,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[语音]','2026-06-28 08:56:19','2026-06-28 08:56:19'),(107,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','[语音]','2026-06-28 08:56:19','2026-06-28 08:56:19'),(108,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 视频通话','2026-06-28 08:57:50','2026-06-28 08:57:50'),(109,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 视频通话','2026-06-28 08:57:50','2026-06-28 08:57:50'),(110,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 视频通话','2026-06-28 08:57:50','2026-06-28 08:57:50'),(111,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 视频通话','2026-06-28 08:58:43','2026-06-28 08:58:43'),(112,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 视频通话','2026-06-28 08:58:43','2026-06-28 08:58:43'),(113,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 视频通话','2026-06-28 08:58:43','2026-06-28 08:58:43'),(114,25,60,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-28 08:59:02','2026-06-28 08:59:02'),(115,25,72,'70e5e7bd-bd92-4aad-899b-6d94124165a5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-28 08:59:02','2026-06-28 08:59:02'),(116,25,69,'a6b42df1-914b-4de7-a277-d7363867b6e5','fcm',0,'Android 推送通道未启用: fcm','ceshi3','来电: 语音通话','2026-06-28 08:59:02','2026-06-28 08:59:02');
/*!40000 ALTER TABLE `push_delivery_logs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `recharge_methods`
--

DROP TABLE IF EXISTS `recharge_methods`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recharge_methods` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `icon` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `type` varchar(20) COLLATE utf8mb4_general_ci NOT NULL,
  `qr_code_url` varchar(500) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `account_info` text COLLATE utf8mb4_general_ci,
  `min_amount` decimal(12,2) DEFAULT '1.00',
  `max_amount` decimal(12,2) DEFAULT '50000.00',
  `remark` varchar(500) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` tinyint DEFAULT '1',
  `sort` bigint DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_recharge_methods_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `recharge_methods`
--

LOCK TABLES `recharge_methods` WRITE;
/*!40000 ALTER TABLE `recharge_methods` DISABLE KEYS */;
/*!40000 ALTER TABLE `recharge_methods` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `recharge_orders`
--

DROP TABLE IF EXISTS `recharge_orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `recharge_orders` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `method_id` bigint unsigned NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `proof_image` varchar(500) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `remark` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `reviewed_by` bigint unsigned DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_recharge_orders_method_id` (`method_id`),
  KEY `idx_recharge_orders_status` (`status`),
  KEY `idx_recharge_orders_reviewed_by` (`reviewed_by`),
  KEY `idx_recharge_orders_created_at` (`created_at`),
  KEY `idx_recharge_orders_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `recharge_orders`
--

LOCK TABLES `recharge_orders` WRITE;
/*!40000 ALTER TABLE `recharge_orders` DISABLE KEYS */;
/*!40000 ALTER TABLE `recharge_orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `red_packet_claims`
--

DROP TABLE IF EXISTS `red_packet_claims`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `red_packet_claims` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `red_packet_id` bigint unsigned NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `is_best` tinyint(1) DEFAULT '0',
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_rp_user` (`red_packet_id`,`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `red_packet_claims`
--

LOCK TABLES `red_packet_claims` WRITE;
/*!40000 ALTER TABLE `red_packet_claims` DISABLE KEYS */;
INSERT INTO `red_packet_claims` VALUES (1,1,3,200.00,0,'2026-06-16 16:01:49'),(2,2,3,50.44,1,'2026-06-16 16:02:14'),(3,3,3,17.33,0,'2026-06-16 16:03:04'),(4,4,3,2.45,0,'2026-06-16 16:04:24'),(5,5,3,2.00,0,'2026-06-16 16:04:52');
/*!40000 ALTER TABLE `red_packet_claims` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `red_packets`
--

DROP TABLE IF EXISTS `red_packets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `red_packets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` char(36) COLLATE utf8mb4_general_ci NOT NULL,
  `sender_id` bigint unsigned NOT NULL,
  `chat_id` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `type` varchar(20) COLLATE utf8mb4_general_ci NOT NULL,
  `total_amount` decimal(12,2) NOT NULL,
  `total_count` bigint NOT NULL,
  `remaining_amount` decimal(12,2) NOT NULL,
  `remaining_count` bigint NOT NULL,
  `message` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'active',
  `expired_at` datetime NOT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_red_packets_uuid` (`uuid`),
  KEY `idx_red_packets_sender_id` (`sender_id`),
  KEY `idx_red_packets_chat_id` (`chat_id`),
  KEY `idx_red_packets_status` (`status`),
  KEY `idx_red_packets_expired_at` (`expired_at`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `red_packets`
--

LOCK TABLES `red_packets` WRITE;
/*!40000 ALTER TABLE `red_packets` DISABLE KEYS */;
INSERT INTO `red_packets` VALUES (1,'1cf7e748-4c4e-48bc-882c-eeb7cb253f62',3,'32ee047e-1dfa-4a1f-9fe2-24633dff7806','lucky',200.00,1,0.00,0,'恭喜发财，大吉大利','finished','2026-06-17 16:01:46','2026-06-16 16:01:46','2026-06-16 16:01:49'),(2,'f8db0803-b2a6-4a48-a86e-4a58d3a51231',3,'32ee047e-1dfa-4a1f-9fe2-24633dff7806','lucky',100.00,2,0.00,1,'恭喜发财，大吉大利','expired','2026-06-17 16:02:10','2026-06-16 16:02:10','2026-06-17 16:02:18'),(3,'063916f5-a137-458a-865e-0f61ce280977',3,'32ee047e-1dfa-4a1f-9fe2-24633dff7806','normal',520.00,30,0.00,29,'恭喜发财，大吉大利','expired','2026-06-17 16:03:01','2026-06-16 16:03:01','2026-06-17 16:03:18'),(4,'91533b60-e152-40da-a604-6ad1b6ebe0b9',3,'32ee047e-1dfa-4a1f-9fe2-24633dff7806','lucky',100.00,12,0.00,11,'恭喜发财，大吉大利','expired','2026-06-17 16:04:14','2026-06-16 16:04:14','2026-06-17 16:04:18'),(5,'1e90d170-724f-4896-84c9-93303a51b96b',3,'32ee047e-1dfa-4a1f-9fe2-24633dff7806','normal',22.00,11,0.00,10,'恭喜发财，大吉大利','expired','2026-06-17 16:04:48','2026-06-16 16:04:48','2026-06-17 16:05:18');
/*!40000 ALTER TABLE `red_packets` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `reports`
--

DROP TABLE IF EXISTS `reports`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `reports` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` varchar(36) NOT NULL,
  `reporter_id` bigint unsigned NOT NULL,
  `target_id` varchar(36) NOT NULL,
  `target_type` varchar(20) NOT NULL,
  `reason` varchar(50) NOT NULL,
  `description` text,
  `status` tinyint DEFAULT '0',
  `processed_by` bigint unsigned DEFAULT NULL,
  `processed_at` datetime(3) DEFAULT NULL,
  `process_note` text,
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_reports_uuid` (`uuid`),
  KEY `idx_reports_reporter_id` (`reporter_id`),
  KEY `idx_reports_target_id` (`target_id`),
  KEY `idx_reports_deleted_at` (`deleted_at`),
  CONSTRAINT `fk_reports_reporter` FOREIGN KEY (`reporter_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `reports`
--

LOCK TABLES `reports` WRITE;
/*!40000 ALTER TABLE `reports` DISABLE KEYS */;
INSERT INTO `reports` VALUES (1,'78a793be-28d1-4d60-92eb-1cbbde62da9c',3,'9a6bd42b-5f44-4d39-a4fe-05657dec1f20','user','spam','测试',0,NULL,NULL,'','2026-06-16 16:25:54.642','2026-06-16 16:25:54.642',NULL);
/*!40000 ALTER TABLE `reports` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `system_broadcasts`
--

DROP TABLE IF EXISTS `system_broadcasts`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `system_broadcasts` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `title` varchar(200) COLLATE utf8mb4_general_ci NOT NULL,
  `content` text COLLATE utf8mb4_general_ci NOT NULL,
  `type` varchar(50) COLLATE utf8mb4_general_ci DEFAULT 'info',
  `online_count` bigint DEFAULT NULL,
  `admin_id` bigint unsigned DEFAULT NULL,
  `admin_name` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_system_broadcasts_created_at` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `system_broadcasts`
--

LOCK TABLES `system_broadcasts` WRITE;
/*!40000 ALTER TABLE `system_broadcasts` DISABLE KEYS */;
/*!40000 ALTER TABLE `system_broadcasts` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `system_settings`
--

DROP TABLE IF EXISTS `system_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `system_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(100) NOT NULL,
  `value` text,
  `type` varchar(20) DEFAULT 'string',
  `remark` varchar(500) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_system_settings_key` (`key`),
  KEY `idx_system_settings_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=63 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `system_settings`
--

LOCK TABLES `system_settings` WRITE;
/*!40000 ALTER TABLE `system_settings` DISABLE KEYS */;
INSERT INTO `system_settings` VALUES (1,'app_update_url','','string','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(2,'app_update_message','','string','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(3,'system_name','im','string','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(4,'system_version','','string','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(5,'register_base_url','','string','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(6,'app_version_ios','','string','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(7,'app_version_android','','string','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(8,'app_force_update','false','bool','','2026-06-18 07:57:18','2026-06-18 07:57:18',NULL),(9,'logo_image_url','https://api1.legg.click/uploads/avatars/2026/06/17/9d28d63f_1781705783604.jpg','string','','2026-06-18 07:57:18','2026-06-27 17:34:20',NULL),(10,'customer_service_url','https://www.google.com/','string','','2026-06-18 07:57:18','2026-06-27 17:34:20',NULL),(11,'xiaomi_app_secret','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(12,'oppo_app_secret','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(13,'custom_portal_enabled','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(14,'allow_register','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(15,'allow_stranger_message','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(16,'burn_after_read_enabled','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(17,'message_crypto_mode','plain','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(18,'ip_rate_limit','60','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(19,'heartbeat_timeout','60','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(20,'agora_enabled','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(21,'enable_moment_post','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(22,'custom_portal_title','客服','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(23,'agora_token_expire','3600','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(24,'apns_key_id','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(25,'fcm_service_account_json','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(26,'max_image_size','10','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(27,'max_file_size','100','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(28,'moment_post_review_enabled','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(29,'custom_portal_url','https://www.bing.com/','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(30,'fcm_project_id','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(31,'hms_app_secret','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(32,'new_user_join_group','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(33,'revoke_message_minutes','2','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(34,'agora_app_id','21404f7bdd0f4d41ae3ddbb3420f70dd','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(35,'apns_bundle_id','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(36,'apns_environment','development','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(37,'fcm_enabled','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(38,'oppo_push_enabled','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(39,'group_max_members','200000','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(40,'channel_max_members','0','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(41,'apns_enabled','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(42,'apns_auth_key','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(43,'xiaomi_push_enabled','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(44,'max_voice_size','20','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(45,'require_invite_code','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(46,'require_phone_bind','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(47,'checkin_enabled','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(48,'custom_portal_icon_url','http://localhost:8081/uploads/discover/2026/06/19/fd035e93_1781851330311.png','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(49,'xiaomi_package_name','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(50,'max_video_size','100','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(51,'new_user_follow_official','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(52,'invite_register_bind_only','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(53,'new_user_join_channel','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(54,'group_invite_require_friend','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(55,'member_only_create_group','true','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(56,'agora_app_certificate','f6b231cddfcf45dc96d7573b59882dd1','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(57,'hms_enabled','false','bool','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(58,'oppo_app_key','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(59,'user_rate_limit','30','int','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(60,'apns_team_id','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(61,'hms_app_id','','string','','2026-06-18 09:08:20','2026-06-27 17:34:20',NULL),(62,'discover_top_image_url','https://api1.legg.click/uploads/avatars/2026/06/17/9d28d63f_1781705783604.jpg','string','','2026-06-18 07:57:18','2026-06-27 17:34:20',NULL);
/*!40000 ALTER TABLE `system_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `third_party_payment_orders`
--

DROP TABLE IF EXISTS `third_party_payment_orders`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `third_party_payment_orders` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `out_trade_no` varchar(64) COLLATE utf8mb4_general_ci NOT NULL,
  `user_id` bigint unsigned NOT NULL,
  `channel` varchar(16) COLLATE utf8mb4_general_ci NOT NULL,
  `client_platform` varchar(16) COLLATE utf8mb4_general_ci NOT NULL,
  `pay_mode` varchar(24) COLLATE utf8mb4_general_ci NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `amount_cents` bigint NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `provider_txn_id` varchar(64) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `extra_json` text COLLATE utf8mb4_general_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `paid_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_third_party_payment_orders_out_trade_no` (`out_trade_no`),
  KEY `idx_third_party_payment_orders_user_id` (`user_id`),
  KEY `idx_third_party_payment_orders_channel` (`channel`),
  KEY `idx_third_party_payment_orders_status` (`status`),
  KEY `idx_third_party_payment_orders_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `third_party_payment_orders`
--

LOCK TABLES `third_party_payment_orders` WRITE;
/*!40000 ALTER TABLE `third_party_payment_orders` DISABLE KEYS */;
/*!40000 ALTER TABLE `third_party_payment_orders` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `topics`
--

DROP TABLE IF EXISTS `topics`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `topics` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(100) NOT NULL,
  `description` varchar(500) DEFAULT NULL,
  `icon` varchar(100) DEFAULT NULL,
  `cover_image` varchar(500) DEFAULT NULL,
  `post_count` bigint DEFAULT '0',
  `follow_count` bigint DEFAULT '0',
  `is_hot` tinyint(1) DEFAULT '0',
  `is_official` tinyint(1) DEFAULT '0',
  `status` tinyint DEFAULT '1',
  `sort` bigint DEFAULT '0',
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_topics_name` (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `topics`
--

LOCK TABLES `topics` WRITE;
/*!40000 ALTER TABLE `topics` DISABLE KEYS */;
/*!40000 ALTER TABLE `topics` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `transactions`
--

DROP TABLE IF EXISTS `transactions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `transactions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `type` varchar(30) COLLATE utf8mb4_general_ci NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `balance_after` decimal(12,2) NOT NULL,
  `related_id` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `related_user_id` bigint unsigned DEFAULT NULL,
  `related_user_name` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `remark` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_transactions_user_id` (`user_id`),
  KEY `idx_transactions_type` (`type`),
  KEY `idx_transactions_related_id` (`related_id`),
  KEY `idx_transactions_related_user_id` (`related_user_id`),
  KEY `idx_transactions_created_at` (`created_at`)
) ENGINE=InnoDB AUTO_INCREMENT=16 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `transactions`
--

LOCK TABLES `transactions` WRITE;
/*!40000 ALTER TABLE `transactions` DISABLE KEYS */;
INSERT INTO `transactions` VALUES (1,3,'admin_recharge',10000.00,10000.00,'',NULL,'','后台充值','2026-06-16 15:59:47'),(2,3,'red_packet_send',-200.00,9800.00,'1cf7e748-4c4e-48bc-882c-eeb7cb253f62',NULL,'','发出红包','2026-06-16 16:01:46'),(3,3,'red_packet_receive',200.00,10000.00,'1cf7e748-4c4e-48bc-882c-eeb7cb253f62',3,'看看','领取红包','2026-06-16 16:01:49'),(4,3,'red_packet_send',-100.00,9900.00,'f8db0803-b2a6-4a48-a86e-4a58d3a51231',NULL,'','发出红包','2026-06-16 16:02:10'),(5,3,'red_packet_receive',50.44,9950.44,'f8db0803-b2a6-4a48-a86e-4a58d3a51231',3,'看看','领取红包','2026-06-16 16:02:14'),(6,3,'red_packet_send',-520.00,9430.44,'063916f5-a137-458a-865e-0f61ce280977',NULL,'','发出红包','2026-06-16 16:03:01'),(7,3,'red_packet_receive',17.33,9447.77,'063916f5-a137-458a-865e-0f61ce280977',3,'看看','领取红包','2026-06-16 16:03:04'),(8,3,'red_packet_send',-100.00,9347.77,'91533b60-e152-40da-a604-6ad1b6ebe0b9',NULL,'','发出红包','2026-06-16 16:04:14'),(9,3,'red_packet_receive',2.45,9350.22,'91533b60-e152-40da-a604-6ad1b6ebe0b9',3,'看看','领取红包','2026-06-16 16:04:24'),(10,3,'red_packet_send',-22.00,9328.22,'1e90d170-724f-4896-84c9-93303a51b96b',NULL,'','发出红包','2026-06-16 16:04:48'),(11,3,'red_packet_receive',2.00,9330.22,'1e90d170-724f-4896-84c9-93303a51b96b',3,'看看','领取红包','2026-06-16 16:04:52'),(12,3,'refund',49.56,9379.78,'f8db0803-b2a6-4a48-a86e-4a58d3a51231',NULL,'','红包过期退回','2026-06-17 16:02:18'),(13,3,'refund',502.67,9882.45,'063916f5-a137-458a-865e-0f61ce280977',NULL,'','红包过期退回','2026-06-17 16:03:18'),(14,3,'refund',97.55,9980.00,'91533b60-e152-40da-a604-6ad1b6ebe0b9',NULL,'','红包过期退回','2026-06-17 16:04:18'),(15,3,'refund',20.00,10000.00,'1e90d170-724f-4896-84c9-93303a51b96b',NULL,'','红包过期退回','2026-06-17 16:05:18');
/*!40000 ALTER TABLE `transactions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `transfers`
--

DROP TABLE IF EXISTS `transfers`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `transfers` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` char(36) COLLATE utf8mb4_general_ci NOT NULL,
  `sender_id` bigint unsigned NOT NULL,
  `receiver_id` bigint unsigned NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `remark` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `expired_at` datetime NOT NULL,
  `accepted_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_transfers_uuid` (`uuid`),
  KEY `idx_transfers_status` (`status`),
  KEY `idx_transfers_expired_at` (`expired_at`),
  KEY `idx_transfers_sender_id` (`sender_id`),
  KEY `idx_transfers_receiver_id` (`receiver_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `transfers`
--

LOCK TABLES `transfers` WRITE;
/*!40000 ALTER TABLE `transfers` DISABLE KEYS */;
/*!40000 ALTER TABLE `transfers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_blocks`
--

DROP TABLE IF EXISTS `user_blocks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_blocks` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `blocked_user_id` bigint unsigned NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_block` (`user_id`,`blocked_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_blocks`
--

LOCK TABLES `user_blocks` WRITE;
/*!40000 ALTER TABLE `user_blocks` DISABLE KEYS */;
/*!40000 ALTER TABLE `user_blocks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_chats`
--

DROP TABLE IF EXISTS `user_chats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_chats` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `chat_id` bigint unsigned NOT NULL,
  `target_id` bigint unsigned DEFAULT NULL,
  `last_msg_id` varchar(36) DEFAULT '',
  `last_msg_seq` bigint unsigned DEFAULT '0',
  `last_msg_time` datetime DEFAULT NULL,
  `last_msg_text` varchar(200) DEFAULT NULL,
  `unread_count` bigint DEFAULT '0',
  `is_pinned` tinyint(1) DEFAULT '0',
  `is_muted` tinyint(1) DEFAULT '0',
  `is_archived` tinyint(1) DEFAULT '0',
  `sort_time` datetime DEFAULT NULL,
  `updated_at` datetime NOT NULL,
  `cleared_at` datetime DEFAULT NULL,
  `last_msg_type` bigint DEFAULT '1',
  `last_msg_sender` varchar(100) DEFAULT NULL,
  `last_read_seq` bigint unsigned DEFAULT '0',
  PRIMARY KEY (`id`),
  KEY `idx_user_chats_target_id` (`target_id`),
  KEY `idx_user_chats_sort_time` (`sort_time`),
  KEY `idx_user_chat` (`user_id`,`chat_id`)
) ENGINE=InnoDB AUTO_INCREMENT=179 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_chats`
--

LOCK TABLES `user_chats` WRITE;
/*!40000 ALTER TABLE `user_chats` DISABLE KEYS */;
INSERT INTO `user_chats` VALUES (3,3,2,0,'',5,'2026-06-24 16:13:26','147',1,0,0,0,'2026-06-24 16:13:26','2026-06-24 16:13:26',NULL,1,'看看',5),(4,4,2,0,'',5,'2026-06-24 16:13:26','147',3,0,0,0,'2026-06-24 16:13:26','2026-06-25 01:55:53',NULL,1,'看看',5),(5,3,3,0,'',4,'2026-06-25 02:29:23','好',0,0,0,0,'2026-06-25 02:29:23','2026-06-25 02:29:23',NULL,1,'看看',4),(6,3,4,0,'',3,'2026-06-17 01:58:57','66',0,0,0,0,'2026-06-17 01:58:57','2026-06-17 01:58:57',NULL,1,'看看',3),(7,4,4,0,'',3,'2026-06-17 01:58:57','66',1,0,0,0,'2026-06-17 01:58:57','2026-06-17 01:59:05',NULL,1,'看看',3),(9,4,1,3,'',36,'2026-06-25 02:29:57','莫',14,0,0,0,'2026-06-25 02:29:57','2026-06-25 02:29:57',NULL,1,'看看',35),(10,3,1,4,'',36,'2026-06-25 02:29:57','莫',12,0,0,0,'2026-06-25 02:29:57','2026-06-25 02:29:57',NULL,1,'看看',36),(11,6,5,1,'',23,'2026-06-29 16:11:49','111',9,0,0,0,'2026-06-29 16:11:49','2026-06-29 16:11:49',NULL,1,'22222222222',23),(12,1,5,6,'',23,'2026-06-29 16:11:49','111',14,0,0,0,'2026-06-29 16:11:49','2026-06-29 16:24:08',NULL,1,'22222222222',23),(17,17,7,0,'',4,'2026-06-22 10:39:06','333',0,0,0,0,'2026-06-22 10:39:06','2026-06-22 10:39:06',NULL,1,'188测试',4),(18,16,7,0,'',4,'2026-06-22 10:39:06','333',2,0,0,0,'2026-06-22 10:39:06','2026-06-22 10:39:28',NULL,1,'188测试',4),(19,16,8,0,'',1,'2026-06-19 06:40:40','1999999测试 创建了频道',0,0,0,0,'2026-06-19 06:40:40','2026-06-19 06:40:41',NULL,99,'',1),(20,6,9,0,'',36,'2026-06-22 10:30:47','22',0,0,0,0,'2026-06-22 10:30:47','2026-06-22 10:30:47',NULL,1,'222',36),(21,1,9,0,'',36,'2026-06-22 10:30:47','22',35,0,0,0,'2026-06-22 10:30:47','2026-06-22 10:30:56',NULL,1,'222',36),(38,6,10,18,'',14,'2026-06-21 14:14:58','66',3,0,0,0,'2026-06-21 14:14:58','2026-06-21 14:14:58',NULL,1,'222',14),(39,18,10,6,'',14,'2026-06-21 14:14:58','66',4,0,0,0,'2026-06-21 14:14:58','2026-06-21 14:14:58',NULL,1,'222',12),(40,16,6,17,'',29,'2026-06-22 09:18:13','123123123123213123213123123123',7,0,0,0,'2026-06-22 09:18:13','2026-06-22 09:18:13',NULL,1,'1999999测试',29),(41,17,6,16,'',29,'2026-06-22 09:18:13','123123123123213123213123123123',4,0,0,0,'2026-06-22 09:18:13','2026-06-22 09:18:13',NULL,1,'1999999测试',29),(42,3,11,16,'',17,'2026-06-25 02:09:12','111',11,0,0,0,'2026-06-25 02:09:12','2026-06-25 02:09:12',NULL,1,'看看',17),(43,16,11,3,'',17,'2026-06-25 02:09:12','111',6,0,0,0,'2026-06-25 02:09:12','2026-06-26 21:31:35',NULL,1,'看看',17),(44,6,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',7,0,0,0,'2026-06-27 14:53:14','2026-06-27 14:53:15',NULL,1,'11122',20),(45,1,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',18,0,0,0,'2026-06-27 14:53:14','2026-06-27 14:53:14',NULL,1,'11122',20),(46,18,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',19,0,0,0,'2026-06-27 14:53:14','2026-06-27 14:53:14',NULL,1,'11122',0),(47,22,13,21,'',3,'2026-06-22 10:53:31','撒大苏打',1,0,0,0,'2026-06-22 10:53:31','2026-06-22 10:54:14',NULL,1,'测试1111',3),(48,21,13,22,'',3,'2026-06-22 10:53:31','撒大苏打',2,0,0,0,'2026-06-22 10:53:31','2026-06-22 10:53:31',NULL,1,'测试1111',3),(49,21,14,0,'',8,'2026-06-22 11:10:30','55555555',0,0,0,0,'2026-06-22 11:10:30','2026-06-22 11:10:30',NULL,2,'测试1111',8),(50,1,15,7,'',2,'2026-06-23 08:04:49','123123',0,0,0,0,'2026-06-23 08:04:49','2026-06-23 08:04:49',NULL,2,'11122',2),(51,7,15,1,'',2,'2026-06-23 08:04:49','123123',2,0,0,0,'2026-06-23 08:04:49','2026-06-23 08:04:49',NULL,2,'11122',0),(52,6,16,7,'',1,'2026-06-22 10:56:34','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"44b5db24-356c-49bc-8733-c6cfc88d8b75\",\"target_name\":\"2\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:56:34','2026-06-22 10:56:34',NULL,99,'',0),(53,7,16,6,'',1,'2026-06-22 10:56:34','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"44b5db24-356c-49bc-8733-c6cfc88d8b75\",\"target_name\":\"2\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:56:34','2026-06-22 10:56:34',NULL,99,'',0),(54,22,14,0,'',8,'2026-06-22 11:10:30','55555555',6,0,0,0,'2026-06-22 11:10:30','2026-06-22 11:10:34',NULL,2,'测试1111',8),(55,1,17,8,'',1,'2026-06-22 10:57:02','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"65c7b4e3-4610-4d9b-ba43-e8919074fd1e\",\"target_name\":\"3\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:57:02','2026-06-25 15:22:28',NULL,99,'',1),(56,8,17,1,'',1,'2026-06-22 10:57:02','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"65c7b4e3-4610-4d9b-ba43-e8919074fd1e\",\"target_name\":\"3\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:57:02','2026-06-22 10:57:02',NULL,99,'',0),(57,6,18,8,'',1,'2026-06-22 10:57:03','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"65c7b4e3-4610-4d9b-ba43-e8919074fd1e\",\"target_name\":\"3\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:57:03','2026-06-22 10:57:03',NULL,99,'',0),(58,8,18,6,'',1,'2026-06-22 10:57:03','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"65c7b4e3-4610-4d9b-ba43-e8919074fd1e\",\"target_name\":\"3\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:57:03','2026-06-22 10:57:03',NULL,99,'',0),(59,1,19,9,'',1,'2026-06-22 10:57:30','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"0a7b6b6f-5387-42b0-bf2f-d6dcb46b541e\",\"target_name\":\"4\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:57:30','2026-06-25 15:20:16',NULL,99,'',1),(60,9,19,1,'',1,'2026-06-22 10:57:30','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"0a7b6b6f-5387-42b0-bf2f-d6dcb46b541e\",\"target_name\":\"4\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:57:30','2026-06-22 10:57:30',NULL,99,'',0),(61,6,20,10,'',1,'2026-06-22 10:57:49','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"5a62b32e-b067-4b03-a917-c738fe37e680\",\"target_name\":\"5\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:57:49','2026-06-22 10:57:49',NULL,99,'',0),(62,10,20,6,'',1,'2026-06-22 10:57:49','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"5a62b32e-b067-4b03-a917-c738fe37e680\",\"target_name\":\"5\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:57:49','2026-06-22 10:57:49',NULL,99,'',0),(63,1,21,10,'',1,'2026-06-22 10:57:49','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"5a62b32e-b067-4b03-a917-c738fe37e680\",\"target_name\":\"5\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:57:49','2026-06-23 08:45:32',NULL,99,'',1),(64,10,21,1,'',1,'2026-06-22 10:57:49','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"5a62b32e-b067-4b03-a917-c738fe37e680\",\"target_name\":\"5\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:57:49','2026-06-22 10:57:49',NULL,99,'',0),(65,1,22,11,'',1,'2026-06-22 10:58:18','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"d2ae4266-3f65-487b-b9a1-e0966b5807c8\",\"target_name\":\"6\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:58:18','2026-06-24 08:29:03',NULL,99,'',1),(66,11,22,1,'',1,'2026-06-22 10:58:18','{\"adder_id\":\"985a5e53-0334-41b2-97a2-7a438eaa15fc\",\"adder_name\":\"11122\",\"target_id\":\"d2ae4266-3f65-487b-b9a1-e0966b5807c8\",\"target_name\":\"6\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:58:18','2026-06-22 10:58:21',NULL,99,'',1),(67,6,23,11,'',1,'2026-06-22 10:58:18','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"d2ae4266-3f65-487b-b9a1-e0966b5807c8\",\"target_name\":\"6\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-22 10:58:18','2026-06-22 10:58:18',NULL,99,'',0),(68,11,23,6,'',1,'2026-06-22 10:58:18','{\"adder_id\":\"8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f\",\"adder_name\":\"222\",\"target_id\":\"d2ae4266-3f65-487b-b9a1-e0966b5807c8\",\"target_name\":\"6\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-22 10:58:18','2026-06-22 10:58:27',NULL,99,'',1),(69,21,24,0,'',13,'2026-06-22 11:05:49','频道发你了',5,0,0,0,'2026-06-22 11:05:49','2026-06-22 11:06:31',NULL,1,'测试22222',13),(70,22,24,0,'',13,'2026-06-22 11:05:49','频道发你了',8,0,0,0,'2026-06-22 11:05:49','2026-06-22 11:05:49',NULL,1,'测试22222',13),(71,1,25,12,'',13,'2026-06-24 07:28:07','111',0,0,0,0,'2026-06-24 07:28:07','2026-06-24 07:28:07',NULL,1,'11122',13),(72,12,25,1,'',13,'2026-06-24 07:28:07','111',13,0,0,0,'2026-06-24 07:28:07','2026-06-24 07:28:07',NULL,1,'11122',0),(74,1,26,22,'',6,'2026-06-22 11:04:57','频道',4,0,0,0,'2026-06-22 11:04:57','2026-06-22 11:04:57',NULL,1,'测试22222',6),(75,22,26,1,'',6,'2026-06-22 11:04:57','频道',2,0,0,0,'2026-06-22 11:04:57','2026-06-22 11:04:57',NULL,1,'测试22222',6),(76,1,27,21,'',4,'2026-06-22 11:13:11','333',1,0,0,0,'2026-06-22 11:13:11','2026-06-22 11:13:11',NULL,2,'11122',4),(77,21,27,1,'',4,'2026-06-22 11:13:11','333',3,0,0,0,'2026-06-22 11:13:11','2026-06-22 11:19:04',NULL,2,'11122',4),(79,24,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',11,0,0,0,'2026-06-27 14:53:14','2026-06-27 14:53:14',NULL,1,'11122',11),(80,24,28,6,'',0,NULL,NULL,0,0,0,0,'2026-06-22 11:24:16','2026-06-22 11:24:16',NULL,1,NULL,0),(81,6,28,24,'',0,NULL,NULL,0,0,0,0,'2026-06-22 11:24:16','2026-06-22 11:24:16',NULL,1,NULL,0),(82,25,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',9,0,0,0,'2026-06-27 14:53:14','2026-06-27 21:36:53',NULL,1,'11122',20),(83,26,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',9,0,0,0,'2026-06-27 14:53:14','2026-06-27 21:38:15',NULL,1,'11122',20),(84,27,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',9,0,0,0,'2026-06-27 14:53:14','2026-06-27 21:47:53',NULL,1,'11122',20),(85,25,29,26,'',5,'2026-06-28 08:49:12','视频通话 cancelled',2,0,0,0,'2026-06-28 08:49:12','2026-06-28 08:49:13',NULL,11,'测试客服',9),(86,26,29,25,'',5,'2026-06-28 08:49:12','视频通话 cancelled',3,0,0,0,'2026-06-28 08:49:12','2026-06-28 08:58:57',NULL,11,'测试客服',9),(87,25,29,26,'',5,'2026-06-28 08:49:12','视频通话 cancelled',2,0,0,0,'2026-06-28 08:49:12','2026-06-28 08:49:13',NULL,11,'测试客服',9),(88,26,29,25,'',5,'2026-06-28 08:49:12','视频通话 cancelled',2,0,0,0,'2026-06-28 08:49:12','2026-06-28 08:58:57',NULL,11,'测试客服',9),(89,25,30,27,'',11,'2026-06-28 08:59:32','语音通话 00:26',7,0,0,0,'2026-06-28 08:59:32','2026-06-28 08:59:45',NULL,11,'ceshi3',14),(90,27,30,25,'',11,'2026-06-28 08:59:32','语音通话 00:26',1,0,0,0,'2026-06-28 08:59:32','2026-06-28 08:59:32',NULL,11,'ceshi3',14),(91,1,31,25,'',0,NULL,NULL,0,0,0,0,'2026-06-23 07:55:53','2026-06-23 07:55:53',NULL,1,NULL,0),(92,25,31,1,'',0,NULL,NULL,0,0,0,0,'2026-06-23 07:55:53','2026-06-23 07:55:53',NULL,1,NULL,0),(93,28,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',9,0,0,0,'2026-06-27 14:53:14','2026-06-27 14:53:14',NULL,1,'11122',0),(96,28,33,0,'',2,'2026-06-23 09:08:10','12312321',0,0,0,0,'2026-06-23 09:08:10','2026-06-23 09:08:10',NULL,1,'15',2),(98,1,32,28,'',69,'2026-06-24 10:57:07','444',0,0,0,0,'2026-06-24 10:57:07','2026-06-24 10:57:07',NULL,1,'11122',69),(99,28,32,1,'',69,'2026-06-24 10:57:07','444',47,0,0,0,'2026-06-24 10:57:07','2026-06-24 10:57:07',NULL,1,'11122',0),(100,29,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',8,0,0,0,'2026-06-27 14:53:14','2026-06-27 14:53:14',NULL,1,'11122',12),(101,29,34,4,'',3,'2026-06-25 02:14:07','哈哈哈',0,0,0,0,'2026-06-25 02:14:07','2026-06-25 02:14:07',NULL,1,'000',3),(102,4,34,29,'',3,'2026-06-25 02:14:07','哈哈哈',3,0,0,0,'2026-06-25 02:14:07','2026-06-25 02:14:13',NULL,1,'000',3),(103,29,35,3,'',2,'2026-06-25 02:15:16','444',1,0,0,0,'2026-06-25 02:15:16','2026-06-25 02:15:16',NULL,1,'看看',0),(104,3,35,29,'',2,'2026-06-25 02:15:16','444',1,0,0,0,'2026-06-25 02:15:16','2026-06-25 02:15:16',NULL,1,'看看',2),(105,30,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',8,0,0,0,'2026-06-27 14:53:14','2026-06-27 14:53:14',NULL,1,'11122',12),(106,30,36,4,'',3,'2026-06-25 02:22:14','@p1111',1,0,0,0,'2026-06-25 02:22:14','2026-06-25 02:22:14',NULL,1,'002',2),(107,4,36,30,'',3,'2026-06-25 02:22:14','@p1111',2,0,0,0,'2026-06-25 02:22:14','2026-06-25 02:22:14',NULL,1,'002',3),(108,31,12,0,'',20,'2026-06-27 14:53:14','Www.googole.com',6,0,0,0,'2026-06-27 14:53:14','2026-06-27 18:14:01',NULL,1,'11122',20),(109,30,37,3,'',1,'2026-06-25 02:28:18','{\"adder_id\":\"a282dd4a-4f3a-4b78-b434-5dc550f7e637\",\"adder_name\":\"3333\",\"target_id\":\"8c0ae608-1124-4aaf-812a-a50a9240142e\",\"target_name\":\"看看\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-25 02:28:18','2026-06-25 02:28:18',NULL,99,'',0),(110,3,37,30,'',1,'2026-06-25 02:28:18','{\"adder_id\":\"a282dd4a-4f3a-4b78-b434-5dc550f7e637\",\"adder_name\":\"3333\",\"target_id\":\"8c0ae608-1124-4aaf-812a-a50a9240142e\",\"target_name\":\"看看\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-25 02:28:18','2026-06-25 02:29:51',NULL,99,'',1),(111,31,38,3,'',2,'2026-06-27 20:49:54','视频通话 cancelled',0,0,0,0,'2026-06-27 20:49:54','2026-06-27 20:49:54',NULL,11,'4444',8),(112,3,38,31,'',2,'2026-06-27 20:49:54','视频通话 cancelled',2,0,0,0,'2026-06-27 20:49:54','2026-06-27 20:49:54',NULL,11,'4444',1),(113,31,4,0,'',0,NULL,NULL,0,0,0,0,'2026-06-25 02:30:57','2026-06-25 02:32:16',NULL,1,NULL,3),(114,31,39,4,'',3,'2026-06-27 20:18:05','视频通话 00:41',0,0,0,0,'2026-06-27 20:18:05','2026-06-27 20:18:19',NULL,11,'4444',10),(115,4,39,31,'',3,'2026-06-27 20:18:05','视频通话 00:41',3,0,0,0,'2026-06-27 20:18:05','2026-06-27 20:18:05',NULL,11,'4444',9),(116,6,40,0,'',2,'2026-06-25 14:45:25','123123',0,0,0,0,'2026-06-25 14:45:25','2026-06-25 14:45:25',NULL,1,'222',2),(118,25,41,0,'',11,'2026-06-27 22:13:45','1',10,0,0,0,'2026-06-27 22:13:45','2026-06-28 08:59:39',NULL,1,'ceshi3',11),(119,26,41,0,'',11,'2026-06-27 22:13:45','1',1,0,0,0,'2026-06-27 22:13:45','2026-06-28 08:59:23',NULL,1,'ceshi3',11),(120,27,41,0,'',11,'2026-06-27 22:13:45','1',9,0,0,0,'2026-06-27 22:13:45','2026-06-27 22:13:45',NULL,1,'ceshi3',11),(166,1,40,0,'',0,NULL,NULL,0,0,0,0,'2026-06-25 18:22:32','2026-06-25 18:22:40',NULL,1,NULL,2),(167,25,42,28,'',0,NULL,NULL,0,0,0,0,'2026-06-26 14:56:56','2026-06-26 14:56:56',NULL,1,NULL,0),(168,28,42,25,'',0,NULL,NULL,0,0,0,0,'2026-06-26 14:56:56','2026-06-26 14:56:56',NULL,1,NULL,0),(169,31,43,16,'',0,'2026-06-27 18:14:51','视频通话 cancelled',0,0,0,0,'2026-06-27 18:14:51','2026-06-27 20:18:22',NULL,11,'',1),(170,16,43,31,'',0,'2026-06-27 18:14:51','视频通话 cancelled',0,0,0,0,'2026-06-27 18:14:51','2026-06-27 18:14:51',NULL,11,'',0),(171,31,44,25,'',1,'2026-06-27 18:15:03','是',0,0,0,0,'2026-06-27 18:15:03','2026-06-27 18:15:03',NULL,1,'4444',1),(172,25,44,31,'',1,'2026-06-27 18:15:03','是',1,0,0,0,'2026-06-27 18:15:03','2026-06-27 21:36:11',NULL,1,'4444',1),(173,27,45,26,'',1,'2026-06-28 08:59:39','{\"adder_id\":\"e5119442-0459-4f26-9a2d-129adb17f695\",\"adder_name\":\"ceshi3\",\"target_id\":\"2db61135-1c12-4d14-a5f7-ac11533afaed\",\"target_name\":\"ceshi2\",\"type\":\"contact_added_system_message\"}',0,0,0,0,'2026-06-28 08:59:39','2026-06-28 08:59:49',NULL,99,'',1),(174,26,45,27,'',1,'2026-06-28 08:59:39','{\"adder_id\":\"e5119442-0459-4f26-9a2d-129adb17f695\",\"adder_name\":\"ceshi3\",\"target_id\":\"2db61135-1c12-4d14-a5f7-ac11533afaed\",\"target_name\":\"ceshi2\",\"type\":\"contact_added_system_message\"}',1,0,0,0,'2026-06-28 08:59:39','2026-06-28 09:00:06',NULL,99,'',1),(175,32,12,0,'',0,'0000-00-00 00:00:00','',0,0,0,0,'2026-06-28 14:30:52','2026-06-28 14:30:52',NULL,1,'',0),(176,25,46,0,'',1,'2026-06-28 15:51:59','测试客服 创建了频道',0,0,0,0,'2026-06-28 15:51:59','2026-06-28 15:53:03',NULL,99,'',1),(177,25,47,0,'',1,'2026-06-28 15:52:37','测试客服 创建了群聊',0,0,0,0,'2026-06-28 15:52:37','2026-06-28 15:52:37',NULL,99,'',1),(178,27,47,0,'',1,'2026-06-28 15:52:37','测试客服 创建了群聊',0,0,0,0,'2026-06-28 15:52:37','2026-06-28 17:15:46',NULL,99,'',1);
/*!40000 ALTER TABLE `user_chats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_checkin_stats`
--

DROP TABLE IF EXISTS `user_checkin_stats`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_checkin_stats` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL COMMENT '用户ID',
  `total_days` int DEFAULT '0' COMMENT '总签到天数',
  `continuous_days` int DEFAULT '0' COMMENT '连续签到天数',
  `last_checkin_date` date DEFAULT NULL COMMENT '最后签到日期',
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_checkin_stats`
--

LOCK TABLES `user_checkin_stats` WRITE;
/*!40000 ALTER TABLE `user_checkin_stats` DISABLE KEYS */;
INSERT INTO `user_checkin_stats` VALUES (1,1,3,1,'2026-06-29','2026-06-23 08:33:22.211','2026-06-29 15:25:44.055'),(2,3,1,1,'2026-06-25','2026-06-25 02:02:40.454','2026-06-25 02:02:40.454'),(3,25,1,1,'2026-06-28','2026-06-28 15:54:31.825','2026-06-28 15:54:31.825'),(4,19,1,1,'2026-07-01','2026-07-01 10:20:28.203','2026-07-01 10:20:28.203');
/*!40000 ALTER TABLE `user_checkin_stats` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_checkins`
--

DROP TABLE IF EXISTS `user_checkins`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_checkins` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL COMMENT '用户ID',
  `checkin_date` varchar(10) NOT NULL COMMENT '签到日期(格式如 2026-06-23)',
  `created_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_date` (`user_id`,`checkin_date`)
) ENGINE=InnoDB AUTO_INCREMENT=10 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_checkins`
--

LOCK TABLES `user_checkins` WRITE;
/*!40000 ALTER TABLE `user_checkins` DISABLE KEYS */;
INSERT INTO `user_checkins` VALUES (2,1,'2026-06-23','2026-06-23 08:33:22.211'),(3,3,'2026-06-25','2026-06-25 02:02:40.454'),(6,1,'2026-06-25','2026-06-25 13:33:52.514'),(7,25,'2026-06-28','2026-06-28 15:54:31.825'),(8,1,'2026-06-29','2026-06-29 15:25:44.053'),(9,19,'2026-07-01','2026-07-01 10:20:28.203');
/*!40000 ALTER TABLE `user_checkins` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_devices`
--

DROP TABLE IF EXISTS `user_devices`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_devices` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `device_id` varchar(100) NOT NULL,
  `device_type` varchar(20) NOT NULL,
  `push_channel` varchar(20) DEFAULT '',
  `device_name` varchar(100) DEFAULT NULL,
  `push_token` varchar(2048) DEFAULT NULL,
  `e2ee_public_key` text,
  `e2ee_public_key_algo` varchar(64) DEFAULT NULL,
  `e2ee_public_key_updated_at` datetime DEFAULT NULL,
  `ip` varchar(50) DEFAULT NULL,
  `location` varchar(100) DEFAULT NULL,
  `last_active` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_devices_user_id` (`user_id`),
  KEY `idx_user_devices_push_channel` (`push_channel`)
) ENGINE=InnoDB AUTO_INCREMENT=87 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_devices`
--

LOCK TABLES `user_devices` WRITE;
/*!40000 ALTER TABLE `user_devices` DISABLE KEYS */;
INSERT INTO `user_devices` VALUES (2,2,'d6bbcfb0-9a49-4dcd-981b-efbb76f66712','android','fcm','Redmi 24090RA29G','ePLtGBZiQqK1il9WBPz8ek:APA91bHZLBXXka-Kl8z0KoIAFKlyzB8SnRDg5Vec3-i7OnuoOGeooKs3Q61Whcd1Rj770k_Bih3koLLQD2Vi_DZ14k5J16G7hZ3MgftEvMH7uvoVcqnBPqI','','',NULL,'45.119.135.147','','2026-06-16 15:27:39','2026-06-16 15:15:21'),(3,3,'7eaea88a-46cd-4ec4-8860-15c699077900','android','fcm','Redmi 24090RA29G','','','',NULL,'45.119.135.147','','2026-06-25 02:30:12','2026-06-16 15:33:30'),(4,2,'dba602a7-8648-410a-be92-5f7ee658f7f0','android','','ROG ASUS_AI2501_A','','','',NULL,'45.119.135.147','','2026-06-16 15:44:02','2026-06-16 15:44:01'),(5,4,'efd64a56-c931-431a-bf15-3b846e404840','android','','ROG ASUS_AI2501_A','','','',NULL,'45.119.135.147','','2026-06-27 20:18:03','2026-06-16 15:46:53'),(6,5,'4325dae6-16fe-4d48-b7e6-17da6bfbecff','android','fcm','itel itel A6611L','cC2rF6RdRtaDC0ILSrqUVK:APA91bGJUj3x-gfDySIcllztIbxwT6H523Z6uWCZ9dtznwtF93OOcKI4UigpP51zdCZuKaWheSOy-D5PowgzN50dZBG6f2DWMQnFisyDpHUYaiGlapyct9c','','',NULL,'27.125.242.236','','2026-06-21 01:38:46','2026-06-17 04:53:55'),(14,6,'67233721-745e-42c7-aa28-549d02d9a5ea','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 07:26:58','2026-06-17 12:51:11'),(16,7,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 07:27:01','2026-06-18 06:37:15'),(17,8,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 06:51:56','2026-06-18 06:48:47'),(18,9,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 06:55:24','2026-06-18 06:52:18'),(19,10,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 06:57:38','2026-06-18 06:55:34'),(20,11,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 06:57:51','2026-06-18 06:57:49'),(21,12,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 07:00:14','2026-06-18 06:58:29'),(22,13,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 07:01:40','2026-06-18 07:00:33'),(23,14,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 07:02:06','2026-06-18 07:02:02'),(24,15,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-18 07:21:13','2026-06-18 07:02:42'),(26,6,'6fc55726-6a57-490a-a266-1b200fa42df9','android','','google sdk_gphone64_arm64','','','',NULL,'74.207.241.28','','2026-06-19 05:26:06','2026-06-18 10:15:59'),(27,16,'c46be0bb-a3ad-45ce-a2b9-db060f5070bb','android','','HONOR SDY-AN00','','','',NULL,'38.45.126.162','','2026-06-20 06:52:20','2026-06-19 05:54:10'),(28,17,'a13c02c9-9329-4f1c-af00-3008d4f7b5f5','android','','OPPO PFGM00','','','',NULL,'38.45.126.162','','2026-06-20 06:52:20','2026-06-19 05:54:12'),(30,6,'54efaf71-2d66-4682-8124-41cf31d258be','android','fcm','google sdk_gphone64_arm64','dnqipDZeQUaH48s0mXyQuj:APA91bGCXfshfy1Hge2EKvPwfmR_7XhnDK5TtyWHdrJfZnpHQ3GxmFuo4ePIBuBYf8NDsTyO9vDHzmI3qYNxuwjRqFWcM01wEgda-hYmY4TjRDBEzt59qaI','','',NULL,'66.235.111.7','','2026-06-21 15:23:57','2026-06-19 07:32:33'),(31,18,'7169774a-7e6f-4a22-a489-895d8296d332','android','','google sdk_gphone64_arm64','','','',NULL,'66.235.111.6','','2026-06-19 10:35:47','2026-06-19 08:16:54'),(32,19,'08276a09-3a54-4dcd-97ff-64bbb93e1459','android','fcm','OPPO PKL110','ckFEby5qSj686h0sp1i2VA:APA91bE6uP7WQA-yJ_5pu4fw0vIvoVtB4wWP25ov_BV8K7ntoKjMQcrKkS-kbSgwkTznmZX2HmCOYhrVAevUvPksrORgxs2YBXHXcO9qIU8Lpk5npTYPGoU','','',NULL,'27.125.240.17','','2026-07-01 10:19:52','2026-06-19 11:50:33'),(34,16,'56533094-eb69-4476-8a1c-465eb72344cc','android','','HONOR SDY-AN00','','','',NULL,'38.45.126.162','','2026-06-20 14:36:27','2026-06-20 13:49:10'),(35,17,'ef5bc51a-e70c-443e-8056-2a9413c46ae9','android','','OPPO PFGM00','','','',NULL,'156.146.45.137','','2026-06-21 15:27:39','2026-06-20 13:49:28'),(36,17,'54efaf71-2d66-4682-8124-41cf31d258be','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.6','','2026-06-20 14:14:36','2026-06-20 14:13:09'),(38,16,'7349e193-76fa-4651-a5ae-0ce8dbcd6a15','web','fcm','Web Browser','ekOzyQVjvsWTw6g1v_WuvW:APA91bFVueCyWkotNk_3CnZ7FrmVNsP82IwAfVmpsYDgv-r3A_f_0ZltRb2iay4mMJ_ZCJt4zUDGJzyA35w8f2pltjBgZiIqTomf9UDA8Pq8FM1vFVb3qQs','','',NULL,'42.200.173.183','','2026-06-22 10:31:22','2026-06-21 12:04:34'),(39,6,'89bf0944-fe2d-4630-a413-c0b2073c2d2d','web','','Web Browser','','','',NULL,'66.235.111.6','','2026-06-21 14:28:24','2026-06-21 12:04:49'),(40,6,'bcd1a1a5-606a-4975-8471-722d6363045a','web','','Web Browser','','','',NULL,'66.235.111.6','','2026-06-21 14:28:29','2026-06-21 14:28:24'),(42,16,'f6c6bf1d-a9ca-413a-bfcd-af59b0ff18ab','android','','OPPO PFGM00','','','',NULL,'156.146.45.137','','2026-06-21 16:33:27','2026-06-21 16:30:53'),(43,6,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','feYlxVBTRICJHMhVDilWMK:APA91bGAyRse8N4Hmcs3f2Cdsa7xQfaQX11kh7tacXwvaG2KjyFGsy3jo4lEJgvsSlvcrBFI28kNLl3STo0etvlPiofMBc_3x0AD0rHLRnkkIeHAZGW0OHo','','',NULL,'66.235.111.7','','2026-06-22 11:38:57','2026-06-22 02:15:58'),(44,20,'6dcfad5c-624c-4289-adba-eee278542f2b','web','fcm','Web Browser','fKbT8kQtrXucKIPT0AFZhr:APA91bFmGBcsW9oSFUGMARrqB9U4VTLkX_wEWk8Mu9hE3JNzfDEZ_Vi0FJTJ7q3s2oTLYDfgEtLSBs5sxlLOJ_CCtg8LssQpJKylRwZWXzriS4SVMhCTN10','','',NULL,'27.109.113.181','','2026-06-27 23:04:13','2026-06-22 08:42:28'),(45,20,'402ccb9e-fb17-41f8-8192-073d95fc8108','web','fcm','Web Browser','eBAzLOay8sRuQEhKfGqVCQ:APA91bERokVjZ_l6GwGeTcpCp3Rcv3w_j0njKI2qDuK9qs5ivbAf8FnUhxTzj95OLs_D5QhW-NV3fYgVkNyvQoSmMoBxsuJjDZ_z4WCVtBRHeor_dRYL7ts','','',NULL,'16.162.47.131','','2026-06-22 08:45:20','2026-06-22 08:44:58'),(46,16,'62221afa-e27d-472d-8afa-fc24e1a19d8d','android','','HONOR SDY-AN00','','','',NULL,'156.146.45.137','','2026-06-22 10:48:09','2026-06-22 09:17:31'),(47,17,'915b2bd6-b42a-4a3f-afb4-1d4b6738b70d','android','','OPPO PFGM00','','','',NULL,'156.146.45.137','','2026-06-22 10:48:11','2026-06-22 09:17:45'),(48,17,'7169774a-7e6f-4a22-a489-895d8296d332','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.7','','2026-06-22 10:37:15','2026-06-22 10:37:12'),(49,16,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.7','','2026-06-22 10:39:04','2026-06-22 10:37:23'),(50,21,'915b2bd6-b42a-4a3f-afb4-1d4b6738b70d','android','','OPPO PFGM00','','','',NULL,'156.146.45.137','','2026-06-22 11:14:19','2026-06-22 10:49:30'),(51,22,'62221afa-e27d-472d-8afa-fc24e1a19d8d','android','','HONOR SDY-AN00','','','',NULL,'156.146.45.137','','2026-06-22 11:14:07','2026-06-22 10:50:29'),(52,7,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.7','','2026-06-22 10:56:26','2026-06-22 10:56:22'),(53,8,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.7','','2026-06-22 10:57:00','2026-06-22 10:56:57'),(54,9,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.7','','2026-06-22 10:57:19','2026-06-22 10:57:16'),(55,10,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.7','','2026-06-22 10:57:47','2026-06-22 10:57:44'),(56,11,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.6','','2026-06-22 10:58:12','2026-06-22 10:58:09'),(57,12,'2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.7','','2026-06-22 10:58:49','2026-06-22 10:58:45'),(58,23,'7169774a-7e6f-4a22-a489-895d8296d332','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.6','','2026-06-22 11:22:44','2026-06-22 11:22:05'),(59,24,'7169774a-7e6f-4a22-a489-895d8296d332','android','fcm','google sdk_gphone64_arm64','','','',NULL,'66.235.111.6','','2026-06-23 07:48:45','2026-06-22 11:23:15'),(60,25,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','fcm','samsung SM-S908E','dVHLDp6vS2aG8k3J2JUWfP:APA91bGwyvnzssVaKeRLdw8zl1TKoaW_cOpkJpPNzro3LTAbW2KEIX7Ygxk3VaTyqHcpHtcTKP8NRoz7bsmcBjltEPZ5K8n2dEuvxgvlWeLt3GE4AIgi7XM','','',NULL,'146.70.14.23','','2026-06-25 16:25:17','2026-06-23 04:22:21'),(61,26,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','fcm','samsung SM-S908E','dVHLDp6vS2aG8k3J2JUWfP:APA91bHH1CHmG7beVnlEWNkxwm_MLpGX7zFlud_1rSHY0OplBmSRRvHr5Ek1juzbaotmYTPjaEEk3uTMfqCgTjTj9HCKnHSVaCzKi5jkhrWqQuqfagIJXzM','','',NULL,'146.70.14.23','','2026-06-25 16:25:09','2026-06-23 04:47:08'),(62,27,'ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','fcm','samsung SM-S908E','dVHLDp6vS2aG8k3J2JUWfP:APA91bGP2KfPKJGdl9lqNAARIWfmCG7ErON1oUO4tm24pS9NPeLxrBSKKU2H1r83wF7GvVCJZ5A8XybC5Fq0aWlmvYU-AnCjyzJIt0yYFd9HaufsCi_3AEQ','','',NULL,'146.70.14.23','','2026-06-25 16:25:04','2026-06-23 04:47:35'),(63,28,'7169774a-7e6f-4a22-a489-895d8296d332','android','fcm','google sdk_gphone64_arm64','','','',NULL,'210.79.151.66','','2026-06-23 09:07:18','2026-06-23 08:39:38'),(64,29,'7eaea88a-46cd-4ec4-8860-15c699077900','android','fcm','Redmi 24090RA29G','','','',NULL,'45.119.135.147','','2026-06-25 02:12:19','2026-06-25 02:12:16'),(65,30,'7eaea88a-46cd-4ec4-8860-15c699077900','android','fcm','Redmi 24090RA29G','','','',NULL,'45.119.135.147','','2026-06-25 02:18:31','2026-06-25 02:16:12'),(66,31,'7eaea88a-46cd-4ec4-8860-15c699077900','android','fcm','Redmi 24090RA29G','dbqAYcY6S06_DJD_2_mTf1:APA91bElVpN8OI7gv4hXzcIu63MHol_0pXi-CO3dY4DbkGsbhXgGQBpOBb4koGVe75O7w1VQ-7Z884T22iEu8VKnSCueDnEqlTH7MadAGB9wWJ6z9M7Knh0','','',NULL,'203.144.92.183','','2026-06-28 18:33:37','2026-06-25 02:18:55'),(67,4,'7eaea88a-46cd-4ec4-8860-15c699077900','android','fcm','Redmi 24090RA29G','','','',NULL,'45.119.135.147','','2026-06-25 02:27:38','2026-06-25 02:27:34'),(68,6,'7483a809-3e5b-4e89-9bc4-ae21c176a5b9','android','','google sdk_gphone64_arm64','','','',NULL,'210.79.151.66','','2026-06-29 16:23:46','2026-06-25 14:20:54'),(69,25,'a6b42df1-914b-4de7-a277-d7363867b6e5','android','fcm','OPPO PKL110','davXb2riQjKAoykm3g4pTg:APA91bEIC9bkcVexGabGnZbvFrfo29SgnOibxbkns-ZI4Cc8-NSH7gsa0nidU-kprOu-tXzXPCrwsJ63q35k_v7i_h5erOpvs0q1CBrP9D3G-7TbBQL84fE','','',NULL,'65.181.16.149','','2026-06-27 21:08:33','2026-06-26 14:52:58'),(70,16,'db2b0357-313b-4526-af63-e0ba4ed95d6e','android','','OPPO PFGM00','','','',NULL,'156.146.45.137','','2026-06-28 14:41:08','2026-06-26 21:31:30'),(71,3,'e82a5b03-c1e1-4e8f-9190-40451df7cde4','android','fcm','Redmi 2406ERN9CC','eeuESmxQTpytIWaeCHwc-W:APA91bHkR7DPJUP409CfuoaH5Wg6g2hp-YD5L6J6dSXTi9P88VSG9leMTPQ4H9V-oGhaS-w_cYJ9ERsZT0T3I2eO33giJY79xKJF9-KD317KyyXE3xcZ5FQ','','',NULL,'45.119.135.147','','2026-06-27 20:57:44','2026-06-27 20:27:52'),(72,25,'70e5e7bd-bd92-4aad-899b-6d94124165a5','android','fcm','OPPO PKL110','fEGKvXMXQmOHNCF8xWQToH:APA91bEBY6GROJSY2e0xu8DqYxx6K-N5koHkJP5OigTHGSsow5kE4h6YImtmRHP_uviUvJWgLgMVtIPejQYLWrQWlYjuhoSZRoNluoSXeyIeXteE1UwEypE','','',NULL,'65.181.16.69','','2026-06-28 21:04:13','2026-06-27 21:34:55'),(73,26,'1f707afa-7ffa-4031-886b-549751113ea9','android','fcm','OPPO PKL110','eBkdxaNNTXW3RCADDBQUpT:APA91bFz3dMnpRqDgJ2XnVKSFBaiAMlvuggqVmO9GVr1EEu1_EzS4TM0sHKvo1xyx4hr4hNj9PRfnuh9iUUjJRDoTHy-JrcCHG4oQ2iKQ4bf6Mwctvm03Wo','','',NULL,'27.125.250.113','','2026-06-28 16:03:45','2026-06-27 21:37:53'),(74,27,'2752a3e0-5c33-4036-b181-50e19dbf1968','android','fcm','vivo V2318A','deNVq8F1Ti2ROH9_TATlwH:APA91bHge6nlXx0227JxDPsXBEUcrAw5Jn9xAa93I7AwcKarPjpIRO3nikPLDdODS4EcQ9vXjCuh8hzku8bQ8G5kkEGsqwRTGLPwbjYqfzgSa3e18XdBhLs','','',NULL,'65.181.16.249','','2026-06-28 18:59:35','2026-06-27 21:47:47'),(75,27,'35f52136-08aa-4b20-ac3c-9403396b62bb','android','fcm','OPPO PKL110','cQDzGYYPTiG9VtV14aRLRD:APA91bEjzMCCm3oszxzt2eU1axIHUw7CFn6LqnG5YzXKYONXX65D6b9VgLRzBadq_6rGL0Ueg-rruN8VaofsoKhjtmy5OP0rGPnX0RiEVSuLmipOXWovX0U','','',NULL,'115.164.61.134','','2026-06-27 22:17:18','2026-06-27 22:09:14'),(76,32,'7169774a-7e6f-4a22-a489-895d8296d332','android','fcm','google sdk_gphone64_arm64','','','',NULL,'210.79.151.66','','2026-06-28 14:30:56','2026-06-28 14:30:52'),(85,1,'7169774a-7e6f-4a22-a489-895d8296d332','android','fcm','google sdk_gphone64_arm64','exNnodB8SCmHtu0Iyv-aun:APA91bH6DYRuuG6Wvd9d5dRKEz6Q9nO570pe0AYTblrbivcFuotmkn6TpUxI_YU90tU0B1eD95pSvXVdIzs8F7uXBgB0LjOZUPk6S4GV9nfk7M2b54_-weI','','',NULL,'210.79.151.66','','2026-06-29 21:14:18','2026-06-29 15:58:16'),(86,1,'89bf0944-fe2d-4630-a413-c0b2073c2d2d','web','','Web Browser','','','',NULL,'210.79.151.66','','2026-06-29 16:40:52','2026-06-29 16:40:44');
/*!40000 ALTER TABLE `user_devices` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_emoji_store_settings`
--

DROP TABLE IF EXISTS `user_emoji_store_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_emoji_store_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `installed_pack_ids` longtext COLLATE utf8mb4_general_ci,
  `favorite_codes` longtext COLLATE utf8mb4_general_ci,
  `custom_emojis` longtext COLLATE utf8mb4_general_ci,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_emoji_store_settings_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_emoji_store_settings`
--

LOCK TABLES `user_emoji_store_settings` WRITE;
/*!40000 ALTER TABLE `user_emoji_store_settings` DISABLE KEYS */;
INSERT INTO `user_emoji_store_settings` VALUES (1,2,'[]','[]','[]','2026-06-16 15:21:17','2026-06-16 15:21:17'),(2,3,'[\"animated_animals\"]','[]','[]','2026-06-16 15:50:05','2026-06-16 15:51:25'),(3,17,'[]','[]','[]','2026-06-19 06:31:36','2026-06-19 06:31:36'),(4,1,'[]','[]','[]','2026-06-20 07:25:31','2026-06-20 07:25:31'),(5,25,'[]','[]','[]','2026-06-25 14:40:03','2026-06-25 14:40:03'),(6,6,'[]','[]','[]','2026-06-26 16:06:48','2026-06-26 16:06:48'),(7,27,'[]','[]','[]','2026-06-28 08:54:47','2026-06-28 08:54:47');
/*!40000 ALTER TABLE `user_emoji_store_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_memberships`
--

DROP TABLE IF EXISTS `user_memberships`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_memberships` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `plan_id` bigint unsigned NOT NULL,
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'active',
  `source` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'wallet',
  `order_id` bigint unsigned DEFAULT NULL,
  `auto_renew` tinyint(1) DEFAULT '0',
  `start_at` datetime NOT NULL,
  `expire_at` datetime NOT NULL,
  `cancelled_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_memberships_user_id` (`user_id`),
  KEY `idx_user_memberships_plan_id` (`plan_id`),
  KEY `idx_user_memberships_status` (`status`),
  KEY `idx_user_memberships_order_id` (`order_id`),
  KEY `idx_user_memberships_start_at` (`start_at`),
  KEY `idx_user_memberships_expire_at` (`expire_at`),
  CONSTRAINT `fk_user_memberships_plan` FOREIGN KEY (`plan_id`) REFERENCES `membership_plans` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=9 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_memberships`
--

LOCK TABLES `user_memberships` WRITE;
/*!40000 ALTER TABLE `user_memberships` DISABLE KEYS */;
INSERT INTO `user_memberships` VALUES (1,16,3,'active','admin',NULL,0,'2026-06-19 06:38:32','2027-06-19 06:38:32',NULL,'2026-06-19 06:38:32','2026-06-19 06:38:32'),(2,16,3,'active','admin',NULL,0,'2026-06-19 06:39:30','2027-06-19 06:39:30',NULL,'2026-06-19 06:39:30','2026-06-19 06:39:30'),(3,7,1,'active','admin',NULL,0,'2026-06-19 07:37:11','2026-07-19 07:37:11',NULL,'2026-06-19 07:37:11','2026-06-19 07:37:11'),(4,6,1,'active','admin',NULL,0,'2026-06-19 07:37:31','2026-07-19 07:37:31',NULL,'2026-06-19 07:37:31','2026-06-19 07:37:31'),(5,21,3,'active','admin',NULL,0,'2026-06-22 10:54:08','2027-06-22 10:54:08',NULL,'2026-06-22 10:54:08','2026-06-22 10:54:08'),(6,28,1,'active','admin',NULL,0,'2026-06-23 09:07:59','2026-07-23 09:07:59',NULL,'2026-06-23 09:07:59','2026-06-23 09:07:59'),(7,3,1,'active','admin',NULL,0,'2026-06-25 14:21:36','2026-07-25 14:21:36',NULL,'2026-06-25 14:21:36','2026-06-25 14:21:36'),(8,25,3,'active','admin',NULL,0,'2026-06-25 14:39:38','2036-06-22 14:39:38',NULL,'2026-06-25 14:39:38','2026-06-25 14:39:38');
/*!40000 ALTER TABLE `user_memberships` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_moment_blocks`
--

DROP TABLE IF EXISTS `user_moment_blocks`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_moment_blocks` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned DEFAULT NULL,
  `blocked_user_id` bigint unsigned DEFAULT NULL,
  `created_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_blocked` (`user_id`,`blocked_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_moment_blocks`
--

LOCK TABLES `user_moment_blocks` WRITE;
/*!40000 ALTER TABLE `user_moment_blocks` DISABLE KEYS */;
/*!40000 ALTER TABLE `user_moment_blocks` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_privacy_settings`
--

DROP TABLE IF EXISTS `user_privacy_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_privacy_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `last_seen_visibility` varchar(20) DEFAULT '所有人',
  `phone_visibility` varchar(20) DEFAULT '联系人',
  `group_invite_permission` varchar(20) DEFAULT '所有人',
  `auto_delete_account` varchar(20) DEFAULT '6 个月',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `allow_phone_search` tinyint(1) DEFAULT '1',
  `allow_short_id_search` tinyint(1) DEFAULT '1',
  `device_lock_enabled` tinyint(1) DEFAULT '0',
  `two_step_enabled` tinyint(1) DEFAULT '0',
  `two_step_password_hash` varchar(255) DEFAULT NULL,
  `two_step_password_hint` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_privacy_settings_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_privacy_settings`
--

LOCK TABLES `user_privacy_settings` WRITE;
/*!40000 ALTER TABLE `user_privacy_settings` DISABLE KEYS */;
INSERT INTO `user_privacy_settings` VALUES (1,1,'所有人','联系人','所有人','6 个月','2026-06-16 13:22:31','2026-06-16 13:22:31',1,1,0,0,'',''),(2,2,'所有人','联系人','所有人','6 个月','2026-06-16 15:15:21','2026-06-16 15:17:20',1,1,0,1,'8d969eef6ecad3c29a3a629280e686cf0c3f5d5a86aff3ca12020c923adc6c92','1..56'),(3,3,'所有人','联系人','所有人','12 个月','2026-06-16 15:33:30','2026-06-25 02:11:22',1,1,0,0,'',''),(4,4,'所有人','联系人','所有人','6 个月','2026-06-16 15:46:53','2026-06-16 15:46:53',1,1,0,0,'',''),(5,5,'所有人','联系人','所有人','6 个月','2026-06-17 04:53:55','2026-06-17 04:53:55',1,1,0,0,'',''),(6,6,'所有人','联系人','所有人','6 个月','2026-06-17 12:51:11','2026-06-17 12:51:11',1,1,0,0,'',''),(7,7,'所有人','联系人','所有人','6 个月','2026-06-18 06:37:15','2026-06-18 06:37:15',1,1,0,0,'',''),(8,8,'所有人','联系人','所有人','6 个月','2026-06-18 06:48:47','2026-06-18 06:48:47',1,1,0,0,'',''),(9,9,'所有人','联系人','所有人','6 个月','2026-06-18 06:52:18','2026-06-18 06:52:18',1,1,0,0,'',''),(10,10,'所有人','联系人','所有人','6 个月','2026-06-18 06:55:34','2026-06-18 06:55:34',1,1,0,0,'',''),(11,11,'所有人','联系人','所有人','6 个月','2026-06-18 06:57:49','2026-06-18 06:57:49',1,1,0,0,'',''),(12,12,'所有人','联系人','所有人','6 个月','2026-06-18 06:58:29','2026-06-18 06:58:29',1,1,0,0,'',''),(13,13,'所有人','联系人','所有人','6 个月','2026-06-18 07:00:33','2026-06-18 07:00:33',1,1,0,0,'',''),(14,14,'所有人','联系人','所有人','6 个月','2026-06-18 07:02:02','2026-06-18 07:02:02',1,1,0,0,'',''),(15,15,'所有人','联系人','所有人','6 个月','2026-06-18 07:02:42','2026-06-18 07:02:42',1,1,0,0,'',''),(16,16,'所有人','联系人','所有人','6 个月','2026-06-19 05:54:10','2026-06-19 05:54:10',1,1,0,0,'',''),(17,17,'所有人','联系人','所有人','6 个月','2026-06-19 05:54:12','2026-06-19 05:54:12',1,1,0,0,'',''),(18,18,'所有人','联系人','所有人','6 个月','2026-06-19 08:16:54','2026-06-19 08:16:54',1,1,0,0,'',''),(19,19,'所有人','联系人','所有人','6 个月','2026-06-19 11:50:33','2026-06-19 11:50:33',1,1,0,0,'',''),(20,20,'所有人','联系人','所有人','6 个月','2026-06-22 08:42:28','2026-06-22 08:42:28',1,1,0,0,'',''),(21,21,'所有人','联系人','所有人','6 个月','2026-06-22 10:49:30','2026-06-22 10:49:30',1,1,0,0,'',''),(22,22,'所有人','联系人','所有人','6 个月','2026-06-22 10:50:29','2026-06-22 10:50:29',1,1,0,0,'',''),(23,23,'所有人','联系人','所有人','6 个月','2026-06-22 11:22:05','2026-06-22 11:22:05',1,1,0,0,'',''),(24,24,'所有人','联系人','所有人','6 个月','2026-06-22 11:23:15','2026-06-22 11:23:15',1,1,0,0,'',''),(25,25,'所有人','联系人','所有人','6 个月','2026-06-23 04:22:21','2026-06-23 04:22:21',1,1,0,0,'',''),(26,26,'所有人','联系人','所有人','6 个月','2026-06-23 04:47:08','2026-06-23 04:47:08',1,1,0,0,'',''),(27,27,'所有人','联系人','所有人','6 个月','2026-06-23 04:47:35','2026-06-23 04:47:35',1,1,0,0,'',''),(28,28,'所有人','联系人','所有人','6 个月','2026-06-23 08:39:38','2026-06-23 08:39:38',1,1,0,0,'',''),(29,29,'所有人','联系人','所有人','6 个月','2026-06-25 02:12:16','2026-06-25 02:12:16',1,1,0,0,'',''),(30,30,'所有人','联系人','所有人','6 个月','2026-06-25 02:16:12','2026-06-25 02:16:12',1,1,0,0,'',''),(31,31,'所有人','联系人','所有人','6 个月','2026-06-25 02:18:55','2026-06-25 02:18:55',1,1,0,0,'',''),(32,32,'所有人','联系人','所有人','6 个月','2026-06-28 14:30:52','2026-06-28 14:30:52',1,1,0,0,'','');
/*!40000 ALTER TABLE `user_privacy_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_push_settings`
--

DROP TABLE IF EXISTS `user_push_settings`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_push_settings` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `show_preview` tinyint(1) DEFAULT '1',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_push_settings_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_push_settings`
--

LOCK TABLES `user_push_settings` WRITE;
/*!40000 ALTER TABLE `user_push_settings` DISABLE KEYS */;
INSERT INTO `user_push_settings` VALUES (1,1,1,'2026-06-16 13:22:33','2026-06-29 21:14:18'),(2,2,1,'2026-06-16 15:15:23','2026-06-16 15:44:03'),(3,3,1,'2026-06-16 15:33:32','2026-06-27 20:57:44'),(4,4,1,'2026-06-16 15:46:55','2026-06-27 20:10:56'),(5,5,1,'2026-06-17 04:53:57','2026-06-20 07:24:16'),(6,6,1,'2026-06-17 12:51:13','2026-06-25 14:20:57'),(7,7,1,'2026-06-18 06:37:17','2026-06-22 10:56:24'),(8,8,1,'2026-06-18 06:48:50','2026-06-22 10:56:59'),(9,9,1,'2026-06-18 06:52:21','2026-06-22 10:57:18'),(10,10,1,'2026-06-18 06:55:37','2026-06-22 10:57:46'),(11,11,1,'2026-06-18 06:57:51','2026-06-22 10:58:11'),(12,12,1,'2026-06-18 06:58:32','2026-06-22 10:58:47'),(13,13,1,'2026-06-18 07:00:36','2026-06-18 07:01:36'),(14,14,1,'2026-06-18 07:02:05','2026-06-18 07:02:05'),(15,15,1,'2026-06-18 07:02:44','2026-06-18 07:02:44'),(16,16,1,'2026-06-19 05:54:13','2026-06-26 21:31:32'),(17,17,1,'2026-06-19 05:54:14','2026-06-22 10:48:12'),(18,18,1,'2026-06-19 08:16:56','2026-06-19 10:35:46'),(19,19,1,'2026-06-19 11:50:35','2026-07-01 10:19:52'),(20,20,1,'2026-06-22 08:42:30','2026-06-27 23:04:10'),(21,21,1,'2026-06-22 10:49:32','2026-06-22 11:14:20'),(22,22,1,'2026-06-22 10:50:31','2026-06-22 11:14:09'),(23,23,1,'2026-06-22 11:22:07','2026-06-22 11:22:07'),(24,24,1,'2026-06-22 11:23:17','2026-06-23 07:47:54'),(25,25,1,'2026-06-23 04:22:24','2026-06-28 15:57:11'),(26,26,1,'2026-06-23 04:47:10','2026-06-28 16:03:45'),(27,27,1,'2026-06-23 04:47:37','2026-06-28 17:15:44'),(28,28,1,'2026-06-23 08:39:41','2026-06-23 09:07:17'),(29,29,1,'2026-06-25 02:12:18','2026-06-25 02:12:18'),(30,30,1,'2026-06-25 02:16:15','2026-06-25 02:16:15'),(31,31,1,'2026-06-25 02:18:57','2026-06-27 18:13:21'),(32,32,1,'2026-06-28 14:30:54','2026-06-28 14:30:54');
/*!40000 ALTER TABLE `user_push_settings` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_relations`
--

DROP TABLE IF EXISTS `user_relations`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_relations` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `friend_id` bigint unsigned NOT NULL,
  `status` tinyint DEFAULT '0',
  `remark` varchar(100) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_user_friend` (`user_id`,`friend_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_relations`
--

LOCK TABLES `user_relations` WRITE;
/*!40000 ALTER TABLE `user_relations` DISABLE KEYS */;
/*!40000 ALTER TABLE `user_relations` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `user_sessions`
--

DROP TABLE IF EXISTS `user_sessions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `user_sessions` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `token` varchar(500) NOT NULL,
  `device_id` varchar(100) DEFAULT NULL,
  `device_type` varchar(20) DEFAULT NULL,
  `device_name` varchar(100) DEFAULT NULL,
  `ip` varchar(50) DEFAULT NULL,
  `location` varchar(100) DEFAULT NULL,
  `last_active` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_sessions_token` (`token`),
  KEY `idx_user_sessions_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=143 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_sessions`
--

LOCK TABLES `user_sessions` WRITE;
/*!40000 ALTER TABLE `user_sessions` DISABLE KEYS */;
INSERT INTO `user_sessions` VALUES (2,2,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMDE4ZDkzNGItZjk4Yy00NWZmLWJiMjktMmQ1YmU3ZTg4NWNkIiwiZGV2aWNlX2lkIjoiZDZiYmNmYjAtOWE0OS00ZGNkLTk4MWItZWZiYjc2ZjY2NzEyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjIyOTIwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDIxNTY1NiwiaWF0IjoxNzgxNjIzNjU2fQ.tOuZXEhX3tWzmt3cyMiokv6LEYleMfnp0NvL2dxkf8g','d6bbcfb0-9a49-4dcd-981b-efbb76f66712','android','Redmi 24090RA29G','45.119.135.147','','2026-06-16 15:27:36','2026-06-16 15:15:21'),(3,3,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGMwYWU2MDgtMTEyNC00YWFmLTgxMmEtYTUwYTkyNDAxNDJlIiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjI0MDEwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk0NTM3OCwiaWF0IjoxNzgyMzUzMzc4fQ.lNrFjwSMdYAXrFuVG-0VXVsBf5XjFqa3wknOaAJ_8Ns','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-25 02:09:39','2026-06-16 15:33:30'),(4,2,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMDE4ZDkzNGItZjk4Yy00NWZmLWJiMjktMmQ1YmU3ZTg4NWNkIiwiZGV2aWNlX2lkIjoiZGJhNjAyYTctODY0OC00MTBhLWJlOTItNWY3ZWU2NThmN2YwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjIyOTIwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDIxNjY0MCwiaWF0IjoxNzgxNjI0NjQwfQ.Kx2kKiWwF9eKHUAaYGhK3rXLKVlkt9iOkIDqm0r-SkY','dba602a7-8648-410a-be92-5f7ee658f7f0','android','ROG ASUS_AI2501_A','45.119.135.147','','2026-06-16 15:44:01','2026-06-16 15:44:01'),(5,4,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOWE2YmQ0MmItNWY0NC00ZDM5LWE0ZmUtMDU2NTdkZWMxZjIwIiwiZGV2aWNlX2lkIjoiZWZkNjRhNTYtYzkzMS00MzFhLWJmMTUtM2I4NDZlNDA0ODQwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjI0ODEzLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTE1NDY1NiwiaWF0IjoxNzgyNTYyNjU2fQ.j4QI8FrH8WwxI-Y2eookSTs2XGU-PJmqEn6n9BFdVDA','efd64a56-c931-431a-bf15-3b846e404840','android','ROG ASUS_AI2501_A','45.119.135.147','','2026-06-27 20:17:37','2026-06-16 15:46:53'),(6,5,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNzY4MTY2YTEtYWJjNS00NTlmLWIyNzQtNjJjYTExNTRmNTlmIiwiZGV2aWNlX2lkIjoiNDMyNWRhZTYtMTZmZS00ZDQ4LWI3ZTYtMTdkYTZiZmJlY2ZmIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjcyMDM0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDU0MzQ1NSwiaWF0IjoxNzgxOTUxNDU1fQ._FeyWMyL3fks7GiBxIpmktNv-An3nHbef_UdN9n3P-M','4325dae6-16fe-4d48-b7e6-17da6bfbecff','android','itel itel A6611L','27.125.244.155','','2026-06-20 10:30:55','2026-06-17 04:53:55'),(14,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiNjcyMzM3MjEtNzQ1ZS00MmM3LWFhMjgtNTQ5ZDAyZDlhNWVhIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM0Njk5MCwiaWF0IjoxNzgxNzU0OTkwfQ.Xq0qiTy1mbjQchM5pWmi3bzdecSEVdHLzbF5lbnqo5c','67233721-745e-42c7-aa28-549d02d9a5ea','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 03:56:31','2026-06-17 12:51:11'),(17,7,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNDRiNWRiMjQtMzU2Yy00OWJjLTg3MzMtYzZjZmM4OGQ4Yjc1IiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY0NjM0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1NzI2NCwiaWF0IjoxNzgxNzY1MjY0fQ.XVyaBUFMjiFuGnRytblsIfoMgepK15C8CBBcKY1oJpM','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 06:47:44','2026-06-18 06:37:15'),(18,7,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNDRiNWRiMjQtMzU2Yy00OWJjLTg3MzMtYzZjZmM4OGQ4Yjc1IiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY0NjM0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1NzI4NCwiaWF0IjoxNzgxNzY1Mjg0fQ.WZwgMsiL_mDDJtMCWZsec6xhO17eK9YqnNRMC82h_N0','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 06:48:04','2026-06-18 06:48:04'),(19,8,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjVjN2I0ZTMtNDYxMC00ZDliLWJhNDMtZTg5MTkwNzRmZDFlIiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1MzI2LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1NzUxMywiaWF0IjoxNzgxNzY1NTEzfQ.6k9F2T-Kc_xvcISygN2Icm8YNPzFjy3NrwTA5CP8nxw','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 06:51:54','2026-06-18 06:48:47'),(20,9,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMGE3YjZiNmYtNTM4Ny00MmIwLWJmMmYtZDZkY2I0NmI1NDFlIiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1NTM4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1NzcyMSwiaWF0IjoxNzgxNzY1NzIxfQ.klL3eEsQmOtSN98_OYUOLuvx0FrJDhQcx4Lu8H0pFzs','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 06:55:21','2026-06-18 06:52:18'),(21,10,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNWE2MmIzMmUtYjA2Ny00YjAzLWE5MTctYzczOGZlMzdlNjgwIiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1NzMzLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1Nzg1NiwiaWF0IjoxNzgxNzY1ODU2fQ.1phk92Tl7LsD-_3BHpIezwZE_aI6vjTSRxQ0DQjkzCs','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 06:57:36','2026-06-18 06:55:34'),(22,11,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZDJhZTQyNjYtM2Y2NS00ODdiLWI5YTEtZTA5NjZiNTgwN2M4IiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1ODY4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1Nzg2OCwiaWF0IjoxNzgxNzY1ODY4fQ.o_wazV1POGiwjAwLimpw0lwagPnW778b9IabgeNrgEs','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 06:57:49','2026-06-18 06:57:49'),(23,12,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNGE4M2NmMzctOTNkYS00OTRhLTk4ZTgtNDY0ZDY1Y2E3OWFmIiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1OTA4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1ODAxMiwiaWF0IjoxNzgxNzY2MDEyfQ.5RzlQxCGqI2mEdrPCAdPW9xYqW99Tt11WYmS9qjopOI','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 07:00:12','2026-06-18 06:58:29'),(24,13,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOWYxMDFkOTEtYjI5Ny00MWI2LWIzNTItNzA3MTliZDQ2YTRjIiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY2MDMzLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1ODA5NywiaWF0IjoxNzgxNzY2MDk3fQ.VV-inYG3RrmiWyIU1FIVB-cUPjvj32l68VWUHQEoEJQ','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 07:01:37','2026-06-18 07:00:33'),(25,14,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNTM0MTcyNzUtZWU1MS00NjI4LWJkOTItMmM1MjhmNThiM2QyIiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY2MTIyLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1ODEyMiwiaWF0IjoxNzgxNzY2MTIyfQ.1lWBFt-GKmffJXWSbGF4WljWcJ7kvNKGb3gVFy0qQUw','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 07:02:02','2026-06-18 07:02:02'),(26,15,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZTBjNDNkYjgtYzUwMi00ZWQ5LTk1ODYtMjZiODQ2NzM4ZWY3IiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY2MTYxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1ODE2MSwiaWF0IjoxNzgxNzY2MTYxfQ.gr4cdIxwcmwCmkwJAdXbWQuLwoVMs7Axk6HiCl7I8HE','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 07:02:42','2026-06-18 07:02:42'),(27,7,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNDRiNWRiMjQtMzU2Yy00OWJjLTg3MzMtYzZjZmM4OGQ4Yjc1IiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY0NjM0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDM1OTI5NCwiaWF0IjoxNzgxNzY3Mjk0fQ.IjycdcwrSxIDM_6v2IgzUtscHIwe2rv1t1IugjZBU08','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-18 07:21:35','2026-06-18 07:21:30'),(29,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiNmZjNTU3MjYtNmE1Ny00OTBhLWEyNjYtMWIyMDBmYTQyZGY5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDQzNzg1MSwiaWF0IjoxNzgxODQ1ODUxfQ.ILNEpAeE8PVPxT06c5fdNKHuYGbDsG4kaZSQY10Mj18','6fc55726-6a57-490a-a266-1b200fa42df9','android','google sdk_gphone64_arm64','74.207.241.28','','2026-06-19 05:10:51','2026-06-18 10:15:59'),(30,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiYzQ2YmUwYmItYTNhZC00NWNlLWEyYjktZGIwNjBmNTA3MGJiIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDQ0NTAxNCwiaWF0IjoxNzgxODUzMDE0fQ.2VCRF1nl6VR1nOMiWsr11pXfgdUU4TLAM75FVvhJ4do','c46be0bb-a3ad-45ce-a2b9-db060f5070bb','android','HONOR SDY-AN00','38.45.126.162','','2026-06-19 07:10:14','2026-06-19 05:54:10'),(31,17,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMjFlNTU4ZDQtYzExZi00ODdlLTgyYTItNjM1ODYyMDg0NDk5IiwiZGV2aWNlX2lkIjoiYTEzYzAyYzktOTMyOS00ZjFjLWFmMDAtMzAwOGQ0ZjdiNWY1Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDQ0NTA1MCwiaWF0IjoxNzgxODUzMDUwfQ.SJdKcS2WnzkSbDNeb4aVzloh-vanu6q-615S1vhVYsw','a13c02c9-9329-4f1c-af00-3008d4f7b5f5','android','OPPO PFGM00','38.45.126.162','','2026-06-19 07:10:51','2026-06-19 05:54:12'),(33,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiNTRlZmFmNzEtMmQ2Ni00NjgyLTgxMjQtNDFjZjMxZDI1OGJlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDU1NjYzNCwiaWF0IjoxNzgxOTY0NjM0fQ.LmEl-TQAFvPUFyhx9ENmmkBBzUzOOAgo_qGLIytpdlc','54efaf71-2d66-4682-8124-41cf31d258be','android','google sdk_gphone64_arm64','66.235.111.7','','2026-06-20 14:10:35','2026-06-19 07:32:33'),(34,18,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYjRmMTUxNDAtNTc1My00MDAwLWE0NzgtMmI2MGMwOTM5ZTYzIiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODU3MDE0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDQ1NzM0NiwiaWF0IjoxNzgxODY1MzQ2fQ.cFiijzROsh97XZ14PFPhIyH20u7IKv8a7UIoEwRykhA','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','66.235.111.7','','2026-06-19 10:35:47','2026-06-19 08:16:54'),(38,19,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYzhmNTk3OWEtNjA1OC00ODYzLTkwZWYtOTljZTNjZjJlOWE1IiwiZGV2aWNlX2lkIjoiMDgyNzZhMDktM2E1NC00ZGNkLTk3ZmYtNjRiYmI5M2UxNDU5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODY5ODMzLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTQ2NDM5MCwiaWF0IjoxNzgyODcyMzkwfQ.DAmFgYyaM2zRn2gym1ixKwOG0XBfF3JH_W5Nj5pB6tc','08276a09-3a54-4dcd-97ff-64bbb93e1459','android','OPPO PKL110','27.125.240.17','','2026-07-01 10:19:50','2026-06-19 11:50:33'),(40,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiNTY1MzMwOTQtZWI2OS00NDc2LThhMWMtNDY1ZWI3MjM0NGNjIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDU1ODE4NiwiaWF0IjoxNzgxOTY2MTg2fQ.GRzwMIUzEywEPmUKE1TqmJYHA2MevorHGG6Y2jdGSdE','56533094-eb69-4476-8a1c-465eb72344cc','android','HONOR SDY-AN00','38.45.126.162','','2026-06-20 14:36:27','2026-06-20 13:49:10'),(41,17,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMjFlNTU4ZDQtYzExZi00ODdlLTgyYTItNjM1ODYyMDg0NDk5IiwiZGV2aWNlX2lkIjoiZWY1YmM1MWEtZTcwYy00NDNlLTgwNTYtMmE5NDEzYzQ2YWU5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDY0NzY1OCwiaWF0IjoxNzgyMDU1NjU4fQ.H2fb4PjwBk5kG9GKPtKNLsfao3KP9fzYThkcG5cuVyQ','ef5bc51a-e70c-443e-8056-2a9413c46ae9','android','OPPO PFGM00','156.146.45.137','','2026-06-21 15:27:38','2026-06-20 13:49:28'),(42,17,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMjFlNTU4ZDQtYzExZi00ODdlLTgyYTItNjM1ODYyMDg0NDk5IiwiZGV2aWNlX2lkIjoiNTRlZmFmNzEtMmQ2Ni00NjgyLTgxMjQtNDFjZjMxZDI1OGJlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDU1Njg3NCwiaWF0IjoxNzgxOTY0ODc0fQ.moeY2EOePeMw50qaXJSynV3SAzJJfzmGQou9Se7-FQQ','54efaf71-2d66-4682-8124-41cf31d258be','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-20 14:14:34','2026-06-20 14:13:09'),(45,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiNzM0OWUxOTMtNzZmYS00NjUxLWE1YWUtMGNlOGRiY2Q2YTE1Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxMTMyOSwiaWF0IjoxNzgyMTE5MzI5fQ.WYTos0WxYTQvQr0PZJC1dauZaOJBZFVghYmf3I7fkP4','7349e193-76fa-4651-a5ae-0ce8dbcd6a15','web','Web Browser','42.200.173.183','','2026-06-22 09:08:50','2026-06-21 12:04:34'),(46,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiODliZjA5NDQtZmUyZC00NjMwLWE0MTMtYzBiMjA3M2MyZDJkIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDY0NDA5NSwiaWF0IjoxNzgyMDUyMDk1fQ.aItJq5-_56dSzy6XICA0BV9zyYmchePmEsqv2nu7w2E','89bf0944-fe2d-4630-a413-c0b2073c2d2d','web','Web Browser','66.235.111.7','','2026-06-21 14:28:15','2026-06-21 12:04:49'),(48,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiNTRlZmFmNzEtMmQ2Ni00NjgyLTgxMjQtNDFjZjMxZDI1OGJlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDY0MTk4MCwiaWF0IjoxNzgyMDQ5OTgwfQ.64zhpSjV1Lj7VXgq2Z64GjdviTX9oo5nUy6lxVAYAAY','54efaf71-2d66-4682-8124-41cf31d258be','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-21 13:53:00','2026-06-21 13:52:36'),(49,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiYmNkMWExYTUtNjA2YS00OTc1LTg0NzEtNzIyZDYzNjMwNDVhIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDY0NDEwNSwiaWF0IjoxNzgyMDUyMTA1fQ.UGpCWECNYrc6LDpZojg8m5g7greYh8W9dDsAelswx9U','bcd1a1a5-606a-4975-8471-722d6363045a','web','Web Browser','66.235.111.7','','2026-06-21 14:28:26','2026-06-21 14:28:24'),(60,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiZjZjNmJmMWQtYTljYS00MTNhLWJmY2QtYWY1OWIwZmYxOGFiIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDY1MTYwNiwiaWF0IjoxNzgyMDU5NjA2fQ.a-herOkCZf8jtvTufcAu11gesrF_w5x1lgwOrmy1RAA','f6c6bf1d-a9ca-413a-bfcd-af59b0ff18ab','android','OPPO PFGM00','156.146.45.137','','2026-06-21 16:33:27','2026-06-21 16:30:53'),(61,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNjE3NSwiaWF0IjoxNzgyMTI0MTc1fQ.xkeun355MI2KjA7LOrXh0J6uA5rkft78eKfylC6F_3Y','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-22 10:29:35','2026-06-22 02:15:58'),(65,20,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYTM0NzdhNjQtYjlmOC00Y2QzLThjODktYmVmMTRmZWRmYTIyIiwiZGV2aWNlX2lkIjoiNmRjZmFkNWMtNjI0Yy00Mjg5LWFkYmEtZWVlMjc4NTQyZjJiIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTE3NzQ3LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcwOTc0NywiaWF0IjoxNzgyMTE3NzQ3fQ.54o4S43UWdbhBZdQNcarTZLSS-fsWvlscbG-7yC7Hn4','6dcfad5c-624c-4289-adba-eee278542f2b','web','Web Browser','79.109.224.231','','2026-06-22 08:42:28','2026-06-22 08:42:28'),(66,20,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYTM0NzdhNjQtYjlmOC00Y2QzLThjODktYmVmMTRmZWRmYTIyIiwiZGV2aWNlX2lkIjoiNDAyY2NiOWUtZmIxNy00MWY4LTgxOTItMDczZDk1ZmM4MTA4Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTE3NzQ3LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcwOTg5OCwiaWF0IjoxNzgyMTE3ODk4fQ.L7yrvJhXMH5_QGzBGDRy0Z2051FdR4E-bbBJKvK95Lw','402ccb9e-fb17-41f8-8192-073d95fc8108','web','Web Browser','16.162.47.131','','2026-06-22 08:44:58','2026-06-22 08:44:58'),(67,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiNzM0OWUxOTMtNzZmYS00NjUxLWE1YWUtMGNlOGRiY2Q2YTE1Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNjI2OCwiaWF0IjoxNzgyMTI0MjY4fQ.4xe-si6XlgUFizgouIGFygOw3nmQkUH45-KyGQPbg_U','7349e193-76fa-4651-a5ae-0ce8dbcd6a15','web','Web Browser','112.120.21.228','','2026-06-22 10:31:09','2026-06-22 09:08:51'),(68,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiNjIyMjFhZmEtZTI3ZC00NzJkLThhZmEtZmMyNGUxYTE5ZDhkIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzI4OSwiaWF0IjoxNzgyMTI1Mjg5fQ.bW--HxUoWyLy4PKRzEm0ZjvwV87KG_nBo6bPzpk0L1w','62221afa-e27d-472d-8afa-fc24e1a19d8d','android','HONOR SDY-AN00','156.146.45.137','','2026-06-22 10:48:09','2026-06-22 09:17:31'),(69,17,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMjFlNTU4ZDQtYzExZi00ODdlLTgyYTItNjM1ODYyMDg0NDk5IiwiZGV2aWNlX2lkIjoiOTE1YjJiZDYtYjQyYS00YTNmLWFmYjQtMWQ0YjY3MzhiNzBkIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzI5MCwiaWF0IjoxNzgyMTI1MjkwfQ.M0Q6cO-Tka6trolGMTbjWU24-TDA3K_dE-8C_sdEWmU','915b2bd6-b42a-4a3f-afb4-1d4b6738b70d','android','OPPO PFGM00','156.146.45.137','','2026-06-22 10:48:10','2026-06-22 09:17:45'),(70,17,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMjFlNTU4ZDQtYzExZi00ODdlLTgyYTItNjM1ODYyMDg0NDk5IiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNjYzMiwiaWF0IjoxNzgyMTI0NjMyfQ.vqeMzC6ZvLLlN-Sa3R845xrGAO3cUzpt4piiPX1K2fI','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','66.235.111.7','','2026-06-22 10:37:12','2026-06-22 10:37:12'),(71,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNjc0MSwiaWF0IjoxNzgyMTI0NzQxfQ.VPpsjFJVDknQbKyyfC5I9iUk3dOv-GtH4gwOWeSd45E','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-22 10:39:02','2026-06-22 10:37:23'),(73,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNjgyMCwiaWF0IjoxNzgyMTI0ODIwfQ.qUETTL_M7QSszZ65vMvfHRirBn6ZVFEl5KTCrIwTRoc','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-22 10:40:21','2026-06-22 10:40:21'),(74,21,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYTlhYzUwZDAtNDVlMS00Mjc0LWIxODYtYzA4NjljY2FlMzNiIiwiZGV2aWNlX2lkIjoiOTE1YjJiZDYtYjQyYS00YTNmLWFmYjQtMWQ0YjY3MzhiNzBkIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTI1MzcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxODg1OCwiaWF0IjoxNzgyMTI2ODU4fQ.UZdLdfVOrQyqULTq5Xgn4T8UfVimdeUI7xHXAToGe5c','915b2bd6-b42a-4a3f-afb4-1d4b6738b70d','android','OPPO PFGM00','156.146.45.137','','2026-06-22 11:14:18','2026-06-22 10:49:30'),(75,22,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjhjZjRlNmItNmRiOS00MDk4LTliMGMtMTI5NTE5NDUzNzEwIiwiZGV2aWNlX2lkIjoiNjIyMjFhZmEtZTI3ZC00NzJkLThhZmEtZmMyNGUxYTE5ZDhkIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTI1NDI5LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxODg0NiwiaWF0IjoxNzgyMTI2ODQ2fQ.pIRvjzhg2PcJRdlM7-ClDWtdpOrNdWxKFFlFaBwz3TU','62221afa-e27d-472d-8afa-fc24e1a19d8d','android','HONOR SDY-AN00','156.146.45.137','','2026-06-22 11:14:07','2026-06-22 10:50:29'),(76,7,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNDRiNWRiMjQtMzU2Yy00OWJjLTg3MzMtYzZjZmM4OGQ4Yjc1IiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY0NjM0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzc4MiwiaWF0IjoxNzgyMTI1NzgyfQ.FfLBY85at3c7QdSUeXxdsTEB7zLncn6Girk8N36ZAWk','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-22 10:56:22','2026-06-22 10:56:22'),(77,8,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjVjN2I0ZTMtNDYxMC00ZDliLWJhNDMtZTg5MTkwNzRmZDFlIiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1MzI2LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzgxNiwiaWF0IjoxNzgyMTI1ODE2fQ.IsaDeeC_jYqpE8LD2vgJL4tpEsqoBQDmtPvucu4f94s','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.7','','2026-06-22 10:56:57','2026-06-22 10:56:57'),(78,9,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMGE3YjZiNmYtNTM4Ny00MmIwLWJmMmYtZDZkY2I0NmI1NDFlIiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1NTM4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzgzNiwiaWF0IjoxNzgyMTI1ODM2fQ.F-v9We8KiNoMnfSbruAyG_lB55TgomqAbUY7rYDmvL4','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-22 10:57:16','2026-06-22 10:57:16'),(79,10,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNWE2MmIzMmUtYjA2Ny00YjAzLWE5MTctYzczOGZlMzdlNjgwIiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1NzMzLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzg2MywiaWF0IjoxNzgyMTI1ODYzfQ.fyFQ_YXCCymbOK_NiQUlVLpFUH871nyBExd-5ubnwLQ','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-22 10:57:44','2026-06-22 10:57:44'),(80,11,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZDJhZTQyNjYtM2Y2NS00ODdiLWI5YTEtZTA5NjZiNTgwN2M4IiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1ODY4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzg4OSwiaWF0IjoxNzgyMTI1ODg5fQ.H4KaLrCU6Xvexd_-T0J0LfO-GyXVyrvbrYIBsFfzO4E','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.7','','2026-06-22 10:58:09','2026-06-22 10:58:09'),(81,12,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNGE4M2NmMzctOTNkYS00OTRhLTk4ZTgtNDY0ZDY1Y2E3OWFmIiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzY1OTA4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxNzkyNSwiaWF0IjoxNzgyMTI1OTI1fQ.WNsMNT2_WU9tZkH7CXK9AJdeokhWPV96tjJuB1cQ3x0','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.7','','2026-06-22 10:58:45','2026-06-22 10:58:45'),(82,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiMmQ4ZmJjNjctZWQ0ZS00ODhiLWJiNjgtNGYwOGNhNDg4MjBlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcyMDMyNiwiaWF0IjoxNzgyMTI4MzI2fQ.4XmXFyml0ajjKAa6STw5US3qPhEAsrGlIcij9puSqmo','2d8fbc67-ed4e-488b-bb68-4f08ca48820e','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-22 11:38:47','2026-06-22 11:00:06'),(83,23,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZGRhZDNiOTAtNzE0Ni00MjQ2LTkyYzItYWQ4OWI1MDEyYWZjIiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTI3MzI0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDcxOTM0OCwiaWF0IjoxNzgyMTI3MzQ4fQ.jD57_votrdosQe-daLsR5onLLhJxWopqQjfXoIMy_S0','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','66.235.111.7','','2026-06-22 11:22:28','2026-06-22 11:22:05'),(84,24,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYWQ2MDdkZjgtMWFiMS00MzNlLWE2YWYtOWYwNDU4ODE5MDQwIiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTI3Mzk1LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDc5MjkyNCwiaWF0IjoxNzgyMjAwOTI0fQ.ZoEZ-PjDLSd1WQ94Kfm6S9TQfTDH5-sCdMsfc6MK-fA','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','66.235.111.6','','2026-06-23 07:48:45','2026-06-22 11:23:15'),(85,25,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZmMzODdiNTYtNjc4MS00NmI5LTgwYWQtMDI2MDc1Y2QwYTg5IiwiZGV2aWNlX2lkIjoiY2E4MDVmNWQtMTVkMS00ZTI3LTllYjktMDJkYWEyMDFiM2JjIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTg4NTQxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDc4MTkyNywiaWF0IjoxNzgyMTg5OTI3fQ.zQm9Sx0JL70w8JREI4LEMOHoZIp9e88TmHQiGfA7jL8','ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','samsung SM-S908E','65.181.17.102','','2026-06-23 04:45:28','2026-06-23 04:22:21'),(86,25,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZmMzODdiNTYtNjc4MS00NmI5LTgwYWQtMDI2MDc1Y2QwYTg5IiwiZGV2aWNlX2lkIjoiY2E4MDVmNWQtMTVkMS00ZTI3LTllYjktMDJkYWEyMDFiM2JjIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTg4NTQxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDc4MTkyOCwiaWF0IjoxNzgyMTg5OTI4fQ.oWGmZFlVJoiJeHsFSGS5sxY3g4Fl7SM5q8DG7-1sJ-g','ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','samsung SM-S908E','65.181.17.102','','2026-06-23 04:45:29','2026-06-23 04:45:29'),(87,25,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZmMzODdiNTYtNjc4MS00NmI5LTgwYWQtMDI2MDc1Y2QwYTg5IiwiZGV2aWNlX2lkIjoiY2E4MDVmNWQtMTVkMS00ZTI3LTllYjktMDJkYWEyMDFiM2JjIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTg4NTQxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDc4MTkyOSwiaWF0IjoxNzgyMTg5OTI5fQ.YR5nSKvmxO6zMte4iUTa3BBnOlidQI7NsA6BljhYp0o','ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','samsung SM-S908E','65.181.17.102','','2026-06-23 04:45:30','2026-06-23 04:45:30'),(88,25,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZmMzODdiNTYtNjc4MS00NmI5LTgwYWQtMDI2MDc1Y2QwYTg5IiwiZGV2aWNlX2lkIjoiY2E4MDVmNWQtMTVkMS00ZTI3LTllYjktMDJkYWEyMDFiM2JjIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTg4NTQxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk2NzkxNiwiaWF0IjoxNzgyMzc1OTE2fQ.niQVBqNgAJfdB7DGy5Ou6ytOO7ehrcwAvwE11yIXcJ8','ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','samsung SM-S908E','146.70.14.23','','2026-06-25 16:25:16','2026-06-23 04:46:33'),(89,26,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMmRiNjExMzUtMWMxMi00ZDE0LWE1ZjctYWMxMTUzM2FmYWVkIiwiZGV2aWNlX2lkIjoiY2E4MDVmNWQtMTVkMS00ZTI3LTllYjktMDJkYWEyMDFiM2JjIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTkwMDI4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk2NzkwOCwiaWF0IjoxNzgyMzc1OTA4fQ.D_BBv6BLAwdiHfuYYuppzFBw8bxUjtgbtQPxYOXMO1c','ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','samsung SM-S908E','146.70.14.23','','2026-06-25 16:25:09','2026-06-23 04:47:08'),(90,27,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZTUxMTk0NDItMDQ1OS00ZjI2LTlhMmQtMTI5YWRiMTdmNjk1IiwiZGV2aWNlX2lkIjoiY2E4MDVmNWQtMTVkMS00ZTI3LTllYjktMDJkYWEyMDFiM2JjIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTkwMDU1LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk2NzkwMywiaWF0IjoxNzgyMzc1OTAzfQ.acvbRfmICMHzFpyYuMGzayVb8UMG7sd7eXdwVw2th6w','ca805f5d-15d1-4e27-9eb9-02daa201b3bc','android','samsung SM-S908E','146.70.14.23','','2026-06-25 16:25:04','2026-06-23 04:47:35'),(92,28,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNmU4YjI2NjUtNjgyMi00MmQxLTlhMmUtOTUxZWFjMTY1OWExIiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMjAzOTc4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDc5NTk3OCwiaWF0IjoxNzgyMjAzOTc4fQ.aD8a58HJtsJl8LJQG8rgpuQ8bbCl397Bb7gORCLA6IM','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','210.79.151.66','','2026-06-23 08:39:38','2026-06-23 08:39:38'),(94,28,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNmU4YjI2NjUtNjgyMi00MmQxLTlhMmUtOTUxZWFjMTY1OWExIiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMjAzOTc4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDc5NzYzNCwiaWF0IjoxNzgyMjA1NjM0fQ.skK92Lx4r0hpAzJE-f_Ngl-T2sfO3OU-zMxwYJp-uDw','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','210.79.151.66','','2026-06-23 09:07:14','2026-06-23 09:07:14'),(99,29,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMjk1YjU1YzgtMjgyOC00YWM0LTg1MDAtZDkyNDhhNGM3ZmQ4IiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMzUzNTM1LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk0NTUzNSwiaWF0IjoxNzgyMzUzNTM1fQ._mKjVa8bGFn7vFXiMi_t_HC9fGLDFhuh4ZpwfstgfOM','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-25 02:12:16','2026-06-25 02:12:16'),(100,3,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGMwYWU2MDgtMTEyNC00YWFmLTgxMmEtYTUwYTkyNDAxNDJlIiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjI0MDEwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk0NTcxMSwiaWF0IjoxNzgyMzUzNzExfQ.f7Bcccxnl3-7QNaBuo4eS8wkxYCfbWl9EOY3dtBCylc','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-25 02:15:11','2026-06-25 02:14:48'),(101,30,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiYTI4MmRkNGEtNGYzYS00Yjc4LWI0MzQtNWRjNTUwZjdlNjM3IiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMzUzNzcyLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk0NTkwNiwiaWF0IjoxNzgyMzUzOTA2fQ.aWSIf-bKi0rNOz0r7Nti8RlPEN8mC2OCWQDo7riiB34','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-25 02:18:26','2026-06-25 02:16:12'),(102,31,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMWQ0MTMxODMtN2U5My00ZmY4LWFmOTgtMDAxZjE1MWRiNmY2IiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMzUzOTM0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk0NTkzNCwiaWF0IjoxNzgyMzUzOTM0fQ.m0F80VOSypjMxZGjTqIF6bSAXqJRt6x2O3OKaWIF7-Y','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-25 02:18:55','2026-06-25 02:18:55'),(103,4,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOWE2YmQ0MmItNWY0NC00ZDM5LWE0ZmUtMDU2NTdkZWMxZjIwIiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjI0ODEzLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk0NjQ1NCwiaWF0IjoxNzgyMzU0NDU0fQ.USQDHbphbG-YNqqnOFXm723I30aXud7uOxRIoA4fme8','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-25 02:27:34','2026-06-25 02:27:34'),(104,3,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGMwYWU2MDgtMTEyNC00YWFmLTgxMmEtYTUwYTkyNDAxNDJlIiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjI0MDEwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NDk0NjYxMSwiaWF0IjoxNzgyMzU0NjExfQ.llurOLO8wamS3C_VOOXzVz_dbC3KG0nu65Nl3E67bEo','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-25 02:30:12','2026-06-25 02:28:12'),(105,31,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMWQ0MTMxODMtN2U5My00ZmY4LWFmOTgtMDAxZjE1MWRiNmY2IiwiZGV2aWNlX2lkIjoiN2VhZWE4OGEtNDZjZC00ZWM0LTg4NjAtMTVjNjk5MDc3OTAwIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMzUzOTM0LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTE1NjQ1MSwiaWF0IjoxNzgyNTY0NDUxfQ.FFoiCvhBbbm8rigvD_Ea6Wag-i1x52nVr0nlyo2hFFI','7eaea88a-46cd-4ec4-8860-15c699077900','android','Redmi 24090RA29G','45.119.135.147','','2026-06-27 20:47:32','2026-06-25 02:30:29'),(106,6,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGRkNGIzZGQtZTc5Ny00ZjllLTg5YWYtNDg1NWI5ZWM3YjhmIiwiZGV2aWNlX2lkIjoiNzQ4M2E4MDktM2U1Yi00ZTg5LTliYzQtYWUyMWMxNzZhNWI5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNzAwNjcwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTA1NTc0OSwiaWF0IjoxNzgyNDYzNzQ5fQ.wGrYOpD1azFN1jE__6zudc_zqdMLLvW3ISMu4j_VdRA','7483a809-3e5b-4e89-9bc4-ae21c176a5b9','android','google sdk_gphone64_arm64','210.79.151.66','','2026-06-26 16:49:10','2026-06-25 14:20:54'),(107,25,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZmMzODdiNTYtNjc4MS00NmI5LTgwYWQtMDI2MDc1Y2QwYTg5IiwiZGV2aWNlX2lkIjoiYTZiNDJkZjEtOTE0Yi00ZGU3LWEyNzctZDczNjM4NjdiNmU1Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTg4NTQxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTE1NzcxMSwiaWF0IjoxNzgyNTY1NzExfQ.pJYaxLFtY1bzTPBw2Dzk7yclrMr6jC6MRIyEmwkh6m0','a6b42df1-914b-4de7-a277-d7363867b6e5','android','OPPO PKL110','65.181.16.149','','2026-06-27 21:08:31','2026-06-26 14:52:58'),(109,16,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNjU3YzQ4OGMtMTE3OS00ODBlLTllODgtNTA1MDE0NDRiZGM1IiwiZGV2aWNlX2lkIjoiZGIyYjAzNTctMzEzYi00NTI2LWFmNjMtZTBiYTRlZDk1ZDZlIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxODQ4NDUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTE0NzI2NiwiaWF0IjoxNzgyNTU1MjY2fQ.lwnwiWZsvDgPH5Vn6QWdSZGikiaropgJzzqjPK2SmZk','db2b0357-313b-4526-af63-e0ba4ed95d6e','android','OPPO PFGM00','156.146.45.137','','2026-06-27 18:14:27','2026-06-26 21:31:30'),(110,3,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOGMwYWU2MDgtMTEyNC00YWFmLTgxMmEtYTUwYTkyNDAxNDJlIiwiZGV2aWNlX2lkIjoiZTgyYTViMDMtYzFlMS00ZThmLTkxOTAtNDA0NTFkZjdjZGU0Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjI0MDEwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTE1NzA2MiwiaWF0IjoxNzgyNTY1MDYyfQ.K0b2Qk0PDfdvNKEHVbdgG2mfXdf_gZU91HCqmUui7ok','e82a5b03-c1e1-4e8f-9190-40451df7cde4','android','Redmi 2406ERN9CC','45.119.135.147','','2026-06-27 20:57:43','2026-06-27 20:27:52'),(111,25,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZmMzODdiNTYtNjc4MS00NmI5LTgwYWQtMDI2MDc1Y2QwYTg5IiwiZGV2aWNlX2lkIjoiNzBlNWU3YmQtYmQ5Mi00YWFkLTg5OWItNmQ5NDEyNDE2NWE1Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTg4NTQxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTI0MzgyNCwiaWF0IjoxNzgyNjUxODI0fQ.4XQZsd_c7Dv07oRTiEtctvAnUwUVv63J3WxEmvM2vr8','70e5e7bd-bd92-4aad-899b-6d94124165a5','android','OPPO PKL110','65.181.16.69','','2026-06-28 21:03:44','2026-06-27 21:34:55'),(112,26,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiMmRiNjExMzUtMWMxMi00ZDE0LWE1ZjctYWMxMTUzM2FmYWVkIiwiZGV2aWNlX2lkIjoiMWY3MDdhZmEtN2ZmYS00MDMxLTg4NmItNTQ5NzUxMTEzZWE5Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTkwMDI4LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTIyNTgyMiwiaWF0IjoxNzgyNjMzODIyfQ.mdizOMKIm9hnl0Ha7KuoveMyBmRBnLTeFSlgeslMh8k','1f707afa-7ffa-4031-886b-549751113ea9','android','OPPO PKL110','27.125.250.113','','2026-06-28 16:03:43','2026-06-27 21:37:53'),(113,27,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZTUxMTk0NDItMDQ1OS00ZjI2LTlhMmQtMTI5YWRiMTdmNjk1IiwiZGV2aWNlX2lkIjoiMjc1MmEzZTAtNWMzMy00MDM2LWIxODEtNTBlMTlkYmYxOTY4Iiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTkwMDU1LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTIzNjM3NCwiaWF0IjoxNzgyNjQ0Mzc0fQ.XlHM96Hed3YfS5g5oShuRxuI12Vto6BOKkV_PNaoajI','2752a3e0-5c33-4036-b181-50e19dbf1968','android','vivo V2318A','65.181.16.249','','2026-06-28 18:59:34','2026-06-27 21:47:47'),(114,27,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiZTUxMTk0NDItMDQ1OS00ZjI2LTlhMmQtMTI5YWRiMTdmNjk1IiwiZGV2aWNlX2lkIjoiMzVmNTIxMzYtMDhhYS00YjIwLWFjM2MtOTQwMzM5NmI2MmJiIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyMTkwMDU1LCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTE2MTc5MCwiaWF0IjoxNzgyNTY5NzkwfQ.UsYPDFhuBWCQvkI3ZOOYfLXDylh4QgZ4BkysCZZ2ZdU','35f52136-08aa-4b20-ac3c-9403396b62bb','android','OPPO PKL110','115.164.61.134','','2026-06-27 22:16:30','2026-06-27 22:09:14'),(115,32,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiNTAyNWYyZTUtYjQ3Yi00OWEzLWEwMGItOThmNGI1YWFiMjFmIiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgyNjI4MjUxLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTIyMDI1MSwiaWF0IjoxNzgyNjI4MjUxfQ.-FTQamWXLMIp6do21lqjt55WPUUcPUE6okGzI4fUAO0','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','210.79.151.66','','2026-06-28 14:30:52','2026-06-28 14:30:52'),(141,1,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOTg1YTVlNTMtMDMzNC00MWIyLTk3YTItN2E0MzhlYWExNWZjIiwiZGV2aWNlX2lkIjoiODliZjA5NDQtZmUyZC00NjMwLWE0MTMtYzBiMjA3M2MyZDJkIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjE2MTUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTMxNDQ1MSwiaWF0IjoxNzgyNzIyNDUxfQ.Vv07m4JIFYl5ootOox-baxG_qD8ZjUOXy3iHBX0KxV0','89bf0944-fe2d-4630-a413-c0b2073c2d2d','web','Web Browser','210.79.151.66','','2026-06-29 16:40:52','2026-06-29 16:40:48'),(142,1,'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyX2lkIjoiOTg1YTVlNTMtMDMzNC00MWIyLTk3YTItN2E0MzhlYWExNWZjIiwiZGV2aWNlX2lkIjoiNzE2OTc3NGEtN2U2Zi00YTIyLWE0ODktODk1ZDgyOTZkMzMyIiwic2Vzc2lvbl92ZXJzaW9uIjoxNzgxNjE2MTUwLCJpc3MiOiJnYW9yYW5pbSIsImV4cCI6MTc4NTMzMDg1NiwiaWF0IjoxNzgyNzM4ODU2fQ.JQ1u0mPRrkT71YCdHbmLd56Ds2eWAtiIUJ7mjafqLHs','7169774a-7e6f-4a22-a489-895d8296d332','android','google sdk_gphone64_arm64','210.79.151.66','','2026-06-29 21:14:16','2026-06-29 20:40:47');
/*!40000 ALTER TABLE `user_sessions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `users`
--

DROP TABLE IF EXISTS `users`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `users` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `uuid` char(36) NOT NULL,
  `phone` varchar(20) DEFAULT NULL,
  `username` varchar(50) NOT NULL,
  `nickname` varchar(100) NOT NULL,
  `avatar` varchar(500) DEFAULT NULL,
  `bio` varchar(500) DEFAULT NULL,
  `status` tinyint DEFAULT '1',
  `enable_whitelist` tinyint(1) DEFAULT NULL,
  `whitelist_ips` longtext,
  `last_seen` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `password` varchar(100) NOT NULL,
  `emoji_avatar` varchar(100) DEFAULT NULL,
  `nickname_color` varchar(20) DEFAULT NULL,
  `ban_reason` varchar(500) DEFAULT NULL,
  `banned_at` datetime DEFAULT NULL,
  `short_id` bigint unsigned DEFAULT NULL,
  `premium_type` varchar(20) DEFAULT NULL,
  `is_member` tinyint(1) DEFAULT '0',
  `badge_text` varchar(50) DEFAULT NULL,
  `badge_color` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_users_uuid` (`uuid`),
  UNIQUE KEY `idx_users_username` (`username`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `idx_users_phone` (`phone`),
  UNIQUE KEY `short_id` (`short_id`),
  UNIQUE KEY `idx_users_short_id` (`short_id`),
  KEY `idx_users_deleted_at` (`deleted_at`),
  KEY `idx_users_is_member` (`is_member`)
) ENGINE=InnoDB AUTO_INCREMENT=33 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
INSERT INTO `users` VALUES (1,'985a5e53-0334-41b2-97a2-7a438eaa15fc','13800138000','13800138000','11122','http://localhost:8081/uploads/avatars/2026/06/17/9d28d63f_1781705783604.jpg','',1,0,'','2026-06-29 21:18:00','2026-06-16 13:22:31','2026-06-29 21:14:17',NULL,'$2a$08$BiJAPIlLWmvHrXkE7099EuNBFyA9W9bmjyqTup9IGvvAQmE1Nzdei','','','',NULL,100000001,'',0,'','#3390EC'),(2,'018d934b-f98c-45ff-bb29-2d5be7e885cd','1300000100','1300000100','急急急','','啊啊啊',1,0,NULL,'2026-06-16 15:46:05','2026-06-16 15:15:21','2026-06-16 15:44:02',NULL,'$2a$08$k3zHD6u7OyOT1Nx6TsZqi.mdha/TKS3PB/qzuAq0ZVZA24ghrVhJy','','bg:1,name:0','',NULL,100000002,'',0,'',''),(3,'8c0ae608-1124-4aaf-812a-a50a9240142e','13000001001','13000001001','0001','http://localhost:8081/uploads/avatars/2026/06/25/281b3bcd_1782352935899.jpg','默默地的人物形象',1,0,NULL,'2026-06-27 20:57:54','2026-06-16 15:33:30','2026-06-27 20:57:43',NULL,'$2a$08$WCQfDLQT37haXVDe9sSJmeU3NULchG4U0Jj8n6SE.3J4OYWz3SLT.','','premium:#F59E0B','',NULL,100000003,'monthly',1,'PREMIUM','#3390EC'),(4,'9a6bd42b-5f44-4d39-a4fe-05657dec1f20','13000001002','13000001002','002','','',1,0,NULL,'2026-06-27 20:18:10','2026-06-16 15:46:53','2026-06-27 20:18:03',NULL,'$2a$08$5t/Q1qpRweTtqQ8PNGAOW.UNJoQ/eQ3Pogx.hwFJatbqPjK9i/ToW','','','',NULL,100000004,'',0,'',''),(5,'768166a1-abc5-459f-b274-62ca1154f59f','16666666666','16666666666','大彬','','',1,0,NULL,'2026-06-21 02:46:39','2026-06-17 04:53:55','2026-06-21 01:38:46',NULL,'$2a$08$JoZZV/6YH.5Jhq9.XRBVIeQo6aRrylTFbASODiWez3Fryw8npwpfy','','','',NULL,100000005,'',0,'',''),(6,'8dd4b3dd-e797-4f9e-89af-4855b9ec7b8f','13800138001','13800138001','22222222222','','',1,0,NULL,'2026-06-29 16:25:40','2026-06-17 12:51:11','2026-06-29 16:23:46',NULL,'$2a$08$7VId/q2x01X8fvjD2jYWk.d1ag8rHZJpEF0yHkQnZamJhudnr2axS','','premium:#F59E0B','',NULL,100000006,'monthly',1,'PREMIUM','#3390EC'),(7,'44b5db24-356c-49bc-8733-c6cfc88d8b75','13800138002','13800138002','2','','',1,0,NULL,'2026-06-22 10:56:47','2026-06-18 06:37:15','2026-06-22 10:56:23',NULL,'$2a$08$lvN4kF.WwKuptUXyr8fTLOsw/6sC9lr/pccdHLTyBqSvUUQcvfw1K','','premium:#F59E0B','',NULL,100000007,'monthly',1,'PREMIUM','#3390EC'),(8,'65c7b4e3-4610-4d9b-ba43-e8919074fd1e','13800138003','13800138003','3','','',1,0,NULL,'2026-06-22 10:57:12','2026-06-18 06:48:47','2026-06-22 10:56:57',NULL,'$2a$08$.SVsamc3A8PTuqE6Am3IXeHJpNoXmRYGfPsSVvGInETsrznyxi4Jy','','','',NULL,100000008,'',0,'',''),(9,'0a7b6b6f-5387-42b0-bf2f-d6dcb46b541e','13800138004','13800138004','4','','',1,0,NULL,'2026-06-22 10:57:39','2026-06-18 06:52:18','2026-06-22 10:57:16',NULL,'$2a$08$yIs0BoPNrtMxfBfsaLvAzubeWqFIJQiGTXnzajOQ8i.P6qu5jut52','','','',NULL,100000009,'',0,'',''),(10,'5a62b32e-b067-4b03-a917-c738fe37e680','13800138005','13800138005','5','','',1,0,NULL,'2026-06-22 10:58:04','2026-06-18 06:55:34','2026-06-22 10:57:44',NULL,'$2a$08$1wbHkDDfnYlXd63epstnC.ZC34C.P/OYRCzDaqny6j0nHwYQQbh4q','','','',NULL,100000010,'',0,'',''),(11,'d2ae4266-3f65-487b-b9a1-e0966b5807c8','13800138006','13800138006','6','','',1,0,NULL,'2026-06-22 10:58:41','2026-06-18 06:57:49','2026-06-22 10:58:09',NULL,'$2a$08$73dlx893kJtzHtI/1i/eAOTGe3MjU8hksw9h.VKi41poim36chiW.','','','',NULL,100000011,'',0,'',''),(12,'4a83cf37-93da-494a-98e8-464d65ca79af','13800138007','13800138007','7','','',1,0,NULL,'2026-06-22 11:00:02','2026-06-18 06:58:29','2026-06-22 10:58:46',NULL,'$2a$08$1M1JBz6Yp7bC0cutmkARt.6rdhWKE208W8fCAJhO7BoV2QXhg7G7y','','','',NULL,100000012,'',0,'',''),(13,'9f101d91-b297-41b6-b352-70719bd46a4c','13800138008','13800138008','8','','',1,0,NULL,'2026-06-18 07:01:48','2026-06-18 07:00:33','2026-06-18 07:01:40',NULL,'$2a$08$b0HH1cYYYBx8pSVlm3F2A.SKNgmMPJvXDrFnrmu/fg/2PHEFiEjqu','','','',NULL,100000013,'',0,'',''),(14,'53417275-ee51-4628-bd92-2c528f58b3d2','13800138009','13800138009','9','','',1,0,NULL,'2026-06-18 07:02:29','2026-06-18 07:02:02','2026-06-18 07:02:06',NULL,'$2a$08$PkprcMDUMN897MNIkSSl4uzeNZeZ8teqwb0RzsR9FBKfr25/CJtay','','','',NULL,100000014,'',0,'',''),(15,'e0c43db8-c502-4ed9-9586-26b846738ef7','13800138010','13800138010','10','','',1,0,NULL,'2026-06-18 07:21:24','2026-06-18 07:02:42','2026-06-18 07:21:13',NULL,'$2a$08$u3D2sadyXx/OoHW4shki7OUPldXv1mvQ8HZGROOspPOKU2nQSNhZe','','','',NULL,100000015,'',0,'',''),(16,'657c488c-1179-480e-9e88-50501444bdc5','19999999999','19999999999','1999999测试','http://localhost:8081/uploads/avatars/2026/06/19/d38be70b_1781848451131.jpg','',1,0,NULL,'2026-06-28 19:38:14','2026-06-19 05:54:10','2026-06-28 14:41:08',NULL,'$2a$08$V7uMbdRgde9KZcKvlQSbe.OxXNFtIF/Al8iKKmhH01Neyl.s.Xj62','','premium:#F59E0B','',NULL,100000016,'yearly',1,'官方人员','#F59E0B'),(17,'21e558d4-c11f-487e-82a2-635862084499','18888888888','18888888888','188测试','http://localhost:8081/uploads/avatars/2026/06/19/24abbaef_1781853053012.jpg','',1,0,NULL,'2026-06-22 10:49:04','2026-06-19 05:54:12','2026-06-22 10:48:11',NULL,'$2a$08$4/zXjx34bgEc7jexncRnY.q.TAwpsh3n8f6Vc4U74y5ZEe6YHLfce','','','',NULL,100000017,'',0,'PREMIUM','#F59E0B'),(18,'b4f15140-5753-4000-a478-2b60c0939e63','13800138011','13800138011','11','','',1,0,NULL,'2026-06-19 10:36:47','2026-06-19 08:16:54','2026-06-19 10:35:47',NULL,'$2a$08$IXcO5rUfsQs3Ozq6Gyn0mOqHmIyRTWNpkF/h08W3tPMHywS.zJhmy','','','',NULL,100000018,'',0,'',''),(19,'c8f5979a-6058-4863-90ef-99ce3cf2e9a5','18883037536','18883037536','刘超','http://localhost:8081/uploads/avatars/2026/06/20/ad483cfd_1781953502519.jpg','',1,0,NULL,'2026-07-01 10:20:48','2026-06-19 11:50:33','2026-07-01 10:19:51',NULL,'$2a$08$hThCtLa7NibSs72fK19mzuXDVH37WqPcR1dDnJ7xaa081O37ud/Mm','','','',NULL,100000019,'',0,'',''),(20,'a3477a64-b9f8-4cd3-8c89-bef14fedfa22','13111111111','13111111111','刘抽','','',1,0,NULL,'2026-06-27 23:04:22','2026-06-22 08:42:28','2026-06-27 23:04:08',NULL,'$2a$08$9mlD5s84IDCjRFFAa2zQa.ndzA9729lkRzkheegqh4CHjpGI0a9mG','','','',NULL,100000020,'',0,'',''),(21,'a9ac50d0-45e1-4274-b186-c0869ccae33b','11111111111','11111111111','测试1111','http://localhost:8081/uploads/avatars/2026/06/22/3353ee70_1782125455609.jpg','',1,0,NULL,'2026-06-23 04:17:08','2026-06-22 10:49:30','2026-06-22 11:14:19',NULL,'$2a$08$GJsoYebw7ONLOBXn.b.39eU4BsRan8gZjMo1OrU44o.LX37p4ND6u','','premium:#F59E0B','',NULL,100000021,'yearly',1,'官方人员','#F59E0B'),(22,'68cf4e6b-6db9-4098-9b0c-129519453710','222222222','222222222','测试22222','http://localhost:8081/uploads/avatars/2026/06/22/f6eba8d3_1782125462414.jpg','',1,0,NULL,'2026-06-23 04:17:07','2026-06-22 10:50:29','2026-06-22 11:14:07',NULL,'$2a$08$YOPJ0TMIBGPc/lau1FY0P.xJ/AE865Vos3iJvxLrCjbpYA8g9R94m','','','',NULL,100000022,'',0,'',''),(23,'ddad3b90-7146-4246-92c2-ad89b5012afc','13800138013','13800138013','13','','',1,0,NULL,'2026-06-22 11:23:28','2026-06-22 11:22:05','2026-06-22 11:22:44',NULL,'$2a$08$.YdPwCXQIoTdn4vXgduHiu0Jp4kh6T4fWi9hh84NVNbx0AhM.FfQe','','','',NULL,100000023,'',0,'',''),(24,'ad607df8-1ab1-433e-a6af-9f0458819040','13800138014','13800138014','14','','',1,0,NULL,'2026-06-23 07:49:44','2026-06-22 11:23:15','2026-06-23 07:48:45',NULL,'$2a$08$XywBfMam/n2JWYSSuhJiWuc0ppNoi2M/JvuU2GtZviNVWsyF/8XAe','','','',NULL,100000024,'',0,'',''),(25,'fc387b56-6781-46b9-80ad-026075cd0a89','13343214321','ceshi','测试客服','','',1,0,NULL,'2026-06-28 21:16:40','2026-06-23 04:22:21','2026-06-28 21:04:13',NULL,'$2a$08$RFFqzmCftIhI.yBqtdz57uVL7m4dpLllBT0NYrcmLZlCDhHWbUR6a','','premium:#F59E0B','',NULL,100000025,'yearly',1,'官方客服','#F59E0B'),(26,'2db61135-1c12-4d14-a5f7-ac11533afaed','13443214321','13443214321','ceshi2','','',1,0,NULL,'2026-06-28 16:04:26','2026-06-23 04:47:08','2026-06-28 16:03:43',NULL,'$2a$08$rwqgzaJaEVQIvLmaO9ETC.Q45J4CTBAfMXt7EndZx9kzFSUssF/TO','','','',NULL,100000026,'',0,'',''),(27,'e5119442-0459-4f26-9a2d-129adb17f695','13543214321','13543214321','ceshi3','','',1,0,NULL,'2026-06-28 18:59:39','2026-06-23 04:47:35','2026-06-28 18:59:35',NULL,'$2a$08$BsuoO1XYdIkIMEj4u8S0xuN8A3TZyJIMLpq5sapeiahIgpAGauHT.','','','',NULL,100000027,'',0,'',''),(28,'6e8b2665-6822-42d1-9a2e-951eac1659a1','13800138015','13800138015','15','','',1,0,NULL,'2026-06-23 09:08:18','2026-06-23 08:39:38','2026-06-23 09:07:59',NULL,'$2a$08$Mx5fbhntpFWty8OkB3ub4ubDOO8TUJP2BtVsE7pTfZx9H1t6sBEWO','','premium:#F59E0B','',NULL,100000028,'monthly',1,'PREMIUM','#3390EC'),(29,'295b55c8-2828-4ac4-8500-d9248a4c7fd8','13000001000','13000001000','000','','',1,0,NULL,'2026-06-25 02:14:40','2026-06-25 02:12:16','2026-06-25 02:12:16',NULL,'$2a$08$3uXdOCsr12mw5UZQTFo6OeqVZSerUgd8fgF/yDPmH8C3qXOQhfpXy','','','',NULL,100000029,'',0,'',''),(30,'a282dd4a-4f3a-4b78-b434-5dc550f7e637','13000001003','13000001003','3333','','',1,0,NULL,'2026-06-25 02:19:26','2026-06-25 02:16:12','2026-06-25 02:18:31',NULL,'$2a$08$ZFADz3MdOrrKUHW3gQJY2ulpGjZlrkw93X.wM9y/Wos440eK2DHeq','','','',NULL,100000030,'',0,'',''),(31,'1d413183-7e93-4ff8-af98-001f151db6f6','13000001004','13000001004','4444','','',1,0,NULL,'2026-06-28 22:14:49','2026-06-25 02:18:55','2026-06-28 18:33:37',NULL,'$2a$08$JTwpLcdJPXgN6Rh29tOvIOH1RsE52SG4SUQLxsJact4VkZrA8r7XK','','','',NULL,100000031,'',0,'',''),(32,'5025f2e5-b47b-49a3-a00b-98f4b5aab21f','13800138018','13800138018','11','','',1,0,NULL,'2026-06-28 14:31:12','2026-06-28 14:30:52','2026-06-28 14:30:52',NULL,'$2a$08$/.AqVGEPDvR6IXfBbgBuJetQxMC8MB8Vv3p88d5AS1M52LP4tXLDK','','','',NULL,100000032,'',0,'','');
/*!40000 ALTER TABLE `users` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `wallets`
--

DROP TABLE IF EXISTS `wallets`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `wallets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `balance` decimal(12,2) DEFAULT '0.00',
  `frozen_balance` decimal(12,2) DEFAULT '0.00',
  `pay_password` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `is_locked` tinyint(1) DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_wallets_user_id` (`user_id`),
  KEY `idx_wallets_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=6 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `wallets`
--

LOCK TABLES `wallets` WRITE;
/*!40000 ALTER TABLE `wallets` DISABLE KEYS */;
INSERT INTO `wallets` VALUES (1,2,0.00,0.00,'$2a$10$Mnno8XwIerZhtllTGHTHlOArvVxjNzhnDJoqe6Ji3ieqHn7hHr9Z2',0,'2026-06-16 15:15:43','2026-06-16 15:16:34',NULL),(2,3,10000.00,0.00,'$2a$10$fIuWpZBsJ8FHLZHm3vIN6eOKUtKMdZ2WunvNXsBwRyunz9ejJZZrW',0,'2026-06-16 15:58:31','2026-06-17 16:05:18',NULL),(3,5,0.00,0.00,'',0,'2026-06-17 04:55:31','2026-06-17 04:55:31',NULL),(4,1,0.00,0.00,'',0,'2026-06-18 06:34:12','2026-06-18 06:34:12',NULL),(5,17,0.00,0.00,'',0,'2026-06-19 06:07:14','2026-06-19 06:07:14',NULL);
/*!40000 ALTER TABLE `wallets` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `withdraw_methods`
--

DROP TABLE IF EXISTS `withdraw_methods`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `withdraw_methods` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `icon` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `fields` text COLLATE utf8mb4_general_ci,
  `min_amount` decimal(12,2) DEFAULT '1.00',
  `max_amount` decimal(12,2) DEFAULT '50000.00',
  `fee` decimal(5,2) DEFAULT '0.00',
  `status` tinyint DEFAULT '1',
  `sort` bigint DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_withdraw_methods_deleted_at` (`deleted_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `withdraw_methods`
--

LOCK TABLES `withdraw_methods` WRITE;
/*!40000 ALTER TABLE `withdraw_methods` DISABLE KEYS */;
/*!40000 ALTER TABLE `withdraw_methods` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `withdraw_requests`
--

DROP TABLE IF EXISTS `withdraw_requests`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `withdraw_requests` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `user_id` bigint unsigned NOT NULL,
  `method_id` bigint unsigned NOT NULL,
  `amount` decimal(12,2) NOT NULL,
  `fee` decimal(12,2) DEFAULT '0.00',
  `actual_amount` decimal(12,2) NOT NULL,
  `form_data` text COLLATE utf8mb4_general_ci,
  `status` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'pending',
  `remark` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `reviewed_by` bigint unsigned DEFAULT NULL,
  `reviewed_at` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_withdraw_requests_user_id` (`user_id`),
  KEY `idx_withdraw_requests_method_id` (`method_id`),
  KEY `idx_withdraw_requests_status` (`status`),
  KEY `idx_withdraw_requests_reviewed_by` (`reviewed_by`),
  KEY `idx_withdraw_requests_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `withdraw_requests`
--

LOCK TABLES `withdraw_requests` WRITE;
/*!40000 ALTER TABLE `withdraw_requests` DISABLE KEYS */;
/*!40000 ALTER TABLE `withdraw_requests` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping events for database 'im'
--

--
-- Dumping routines for database 'im'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-07-01 19:27:45

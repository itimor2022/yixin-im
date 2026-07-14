-- MySQL dump 10.13  Distrib 8.0.45, for Linux (x86_64)
--
-- Host: localhost    Database: im
-- ------------------------------------------------------
-- Server version	8.0.45
--
-- Fresh/clean database seed (no user or operational traces)
-- Default admin: username=admin  password=123456  (change after first login)
--

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `admin_login_logs`
--

LOCK TABLES `admin_login_logs` WRITE;
/*!40000 ALTER TABLE `admin_login_logs` DISABLE KEYS */;
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
  `whitelist_ips` text,
  `last_login_at` datetime DEFAULT NULL,
  `last_login_ip` varchar(50) DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_admins_username` (`username`),
  UNIQUE KEY `idx_admins_email` (`email`),
  KEY `idx_admins_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `admins`
--

LOCK TABLES `admins` WRITE;
/*!40000 ALTER TABLE `admins` DISABLE KEYS */;
INSERT INTO `admins` VALUES (1,'admin','$2a$10$17dqS3t1FJ6TRiHYdoacFuHYECtxRJJKIcmBuZP9VGRvGnhhB4Aim','超级管理员','admin@grimimim.com',NULL,'super_admin',1,NULL,NULL,NULL,'2026-01-01 00:00:00','2026-01-01 00:00:00',NULL);
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `banned_words`
--

LOCK TABLES `banned_words` WRITE;
/*!40000 ALTER TABLE `banned_words` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `calls`
--

LOCK TABLES `calls` WRITE;
/*!40000 ALTER TABLE `calls` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `chat_members`
--

LOCK TABLES `chat_members` WRITE;
/*!40000 ALTER TABLE `chat_members` DISABLE KEYS */;
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
  `fake_member_count` bigint NOT NULL DEFAULT '0',
  `fake_online_count` bigint NOT NULL DEFAULT '0',
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `chats`
--

LOCK TABLES `chats` WRITE;
/*!40000 ALTER TABLE `chats` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `contacts`
--

LOCK TABLES `contacts` WRITE;
/*!40000 ALTER TABLE `contacts` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `discover_items`
--

LOCK TABLES `discover_items` WRITE;
/*!40000 ALTER TABLE `discover_items` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `emoji_store_pack_catalogs`
--

LOCK TABLES `emoji_store_pack_catalogs` WRITE;
/*!40000 ALTER TABLE `emoji_store_pack_catalogs` DISABLE KEYS */;
INSERT INTO `emoji_store_pack_catalogs` VALUES (1,'animated_faces','动态笑脸','丰富的表情动画','😂','joy.json','[\"joy.json\",\"laughing.json\",\"smiling.json\",\"wink.json\",\"heart_eyes.json\",\"blush.json\",\"yum.json\",\"relieved.json\",\"star_eyes.json\",\"smirk.json\",\"unamused.json\",\"sweat.json\",\"pensive.json\",\"confused.json\",\"confounded.json\",\"kissing.json\",\"kiss.json\",\"kissing_closed.json\",\"stuck_out.json\",\"wink_tongue.json\",\"disappointed.json\",\"worried.json\",\"surprised.json\",\"crying.json\",\"triumph.json\",\"frowning.json\",\"anguished.json\",\"fearful.json\",\"weary.json\",\"sleepy.json\",\"tired.json\",\"grimacing.json\",\"loudly_crying.json\",\"scream.json\",\"astonished.json\",\"flushed.json\",\"angry.json\",\"thinking.json\",\"sunglasses.json\",\"hot.json\",\"cold.json\",\"hug.json\",\"shush.json\",\"vomit.json\",\"sleeping.json\",\"devil.json\",\"angel.json\",\"exploding_head.json\"]',1,1,1,'2026-01-01 00:00:00','2026-01-01 00:00:00'),(2,'animated_animals','动态动物','可爱的动物动画','🐱','cat.json','[\"dog.json\",\"cat.json\",\"pig.json\",\"monkey.json\",\"monkey_face.json\",\"rabbit.json\",\"tiger.json\",\"frog.json\",\"bird.json\",\"hatching_chick.json\",\"baby_chick.json\",\"hatched_chick.json\",\"butterfly.json\",\"bee.json\",\"turtle.json\",\"snake.json\",\"dragon.json\",\"octopus.json\",\"dolphin.json\",\"whale.json\",\"fish.json\",\"unicorn.json\"]',2,1,1,'2026-01-01 00:00:00','2026-01-01 00:00:00'),(3,'animated_nature','动态自然','自然元素动画','🌈','rainbow.json','[\"rainbow.json\",\"snowflake.json\",\"lightning.json\",\"rose.json\",\"four_leaf.json\"]',3,1,1,'2026-01-01 00:00:00','2026-01-01 00:00:00'),(4,'animated_gestures','动态手势','手势表情动画','👍','thumbs_up.json','[\"thumbs_up.json\",\"thumbs_down.json\",\"clap.json\",\"wave.json\",\"ok.json\",\"muscle.json\",\"pray.json\",\"eyes.json\",\"raised_hands.json\",\"point_up.json\",\"point_down.json\",\"point_left.json\",\"point_right.json\",\"fist.json\",\"v_sign.json\",\"call_me.json\",\"love_you.json\"]',4,1,1,'2026-01-01 00:00:00','2026-01-01 00:00:00'),(5,'animated_symbols','动态爱心','爱心和符号动画','❤️','heart.json','[\"heart.json\",\"orange_heart.json\",\"yellow_heart.json\",\"green_heart.json\",\"blue_heart.json\",\"purple_heart.json\",\"broken_heart.json\",\"sparkling_heart.json\",\"heartbeat.json\",\"fire.json\",\"hundred.json\",\"sparkles.json\",\"party.json\",\"tada.json\",\"rocket.json\",\"ghost.json\",\"skull.json\",\"poop.json\"]',5,1,1,'2026-01-01 00:00:00','2026-01-01 00:00:00');
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `invite_codes`
--

LOCK TABLES `invite_codes` WRITE;
/*!40000 ALTER TABLE `invite_codes` DISABLE KEYS */;
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
INSERT INTO `membership_plans` VALUES (1,'月度会员','monthly',30,28.00,38.00,'PREMIUM','#3390EC','适合先体验高级功能的用户','["会员徽章","更高上传限制","高级贴纸权限","更多会话置顶"]',1,1,'2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(2,'季度会员','quarterly',90,78.00,114.00,'PREMIUM','#8B5CF6','性价比更高，适合稳定使用','["会员徽章","更高上传限制","高级贴纸权限","更多会话置顶"]',1,2,'2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(3,'年度会员','yearly',365,298.00,456.00,'PREMIUM','#F59E0B','最划算，适合长期使用','["会员徽章","更高上传限制","高级贴纸权限","更多会话置顶"]',1,3,'2026-01-01 00:00:00','2026-01-01 00:00:00',NULL);
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `moment_comments`
--

LOCK TABLES `moment_comments` WRITE;
/*!40000 ALTER TABLE `moment_comments` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `moment_likes`
--

LOCK TABLES `moment_likes` WRITE;
/*!40000 ALTER TABLE `moment_likes` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `moments`
--

LOCK TABLES `moments` WRITE;
/*!40000 ALTER TABLE `moments` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `official_groups`
--

LOCK TABLES `official_groups` WRITE;
/*!40000 ALTER TABLE `official_groups` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `official_users`
--

LOCK TABLES `official_users` WRITE;
/*!40000 ALTER TABLE `official_users` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `popup_announcements`
--

LOCK TABLES `popup_announcements` WRITE;
/*!40000 ALTER TABLE `popup_announcements` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `push_delivery_logs`
--

LOCK TABLES `push_delivery_logs` WRITE;
/*!40000 ALTER TABLE `push_delivery_logs` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `red_packet_claims`
--

LOCK TABLES `red_packet_claims` WRITE;
/*!40000 ALTER TABLE `red_packet_claims` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `red_packets`
--

LOCK TABLES `red_packets` WRITE;
/*!40000 ALTER TABLE `red_packets` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `reports`
--

LOCK TABLES `reports` WRITE;
/*!40000 ALTER TABLE `reports` DISABLE KEYS */;
/*!40000 ALTER TABLE `reports` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `role_menus`
--

DROP TABLE IF EXISTS `role_menus`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `role_menus` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `role` varchar(30) COLLATE utf8mb4_general_ci NOT NULL,
  `menu_keys` text COLLATE utf8mb4_general_ci,
  `updated_at` datetime NOT NULL,
  `created_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_role_menus_role` (`role`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `role_menus`
--

LOCK TABLES `role_menus` WRITE;
/*!40000 ALTER TABLE `role_menus` DISABLE KEYS */;
/*!40000 ALTER TABLE `role_menus` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `roles`
--

DROP TABLE IF EXISTS `roles`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `roles` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `key` varchar(30) COLLATE utf8mb4_general_ci NOT NULL,
  `name` varchar(50) COLLATE utf8mb4_general_ci NOT NULL,
  `description` varchar(200) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `code` varchar(20) COLLATE utf8mb4_general_ci NOT NULL DEFAULT 'R_ADMIN',
  `is_built_in` tinyint(1) DEFAULT '0',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_roles_key` (`key`)
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `roles`
--

LOCK TABLES `roles` WRITE;
/*!40000 ALTER TABLE `roles` DISABLE KEYS */;
INSERT INTO `roles` VALUES (1,'super_admin','超级管理员','内置超级管理员，拥有全部权限','R_SUPER',1,'2026-01-01 00:00:00','2026-01-01 00:00:00'),(2,'admin','管理员','系统管理员，拥有除超管专有能力外的所有菜单','R_ADMIN',1,'2026-01-01 00:00:00','2026-01-01 00:00:00'),(3,'operator','运营','日常运营人员，可根据菜单权限限制访问范围','R_ADMIN',1,'2026-01-01 00:00:00','2026-01-01 00:00:00'),(4,'demo_admin','演示账号','只读演示账号，不能进行任何写操作','R_DEMO',1,'2026-01-01 00:00:00','2026-01-01 00:00:00');
/*!40000 ALTER TABLE `roles` ENABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
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
) ENGINE=InnoDB AUTO_INCREMENT=64 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `system_settings`
--

LOCK TABLES `system_settings` WRITE;
/*!40000 ALTER TABLE `system_settings` DISABLE KEYS */;
INSERT INTO `system_settings` VALUES (1,'app_update_url','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(2,'app_update_message','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(3,'system_name','im','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(4,'system_version','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(5,'register_base_url','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(6,'app_version_ios','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(7,'app_version_android','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(8,'app_force_update','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(9,'logo_image_url','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(10,'customer_service_url','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(11,'xiaomi_app_secret','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(12,'oppo_app_secret','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(13,'custom_portal_enabled','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(14,'allow_register','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(15,'allow_stranger_message','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(16,'burn_after_read_enabled','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(17,'message_crypto_mode','plain','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(18,'ip_rate_limit','60','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(19,'heartbeat_timeout','60','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(20,'agora_enabled','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(21,'enable_moment_post','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(22,'custom_portal_title','客服','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(23,'agora_token_expire','3600','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(24,'apns_key_id','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(25,'fcm_service_account_json','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(26,'max_image_size','10','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(27,'max_file_size','100','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(28,'moment_post_review_enabled','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(29,'custom_portal_url','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(30,'fcm_project_id','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(31,'hms_app_secret','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(32,'new_user_join_group','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(33,'revoke_message_minutes','2','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(34,'agora_app_id','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(35,'apns_bundle_id','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(36,'apns_environment','development','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(37,'fcm_enabled','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(38,'oppo_push_enabled','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(39,'group_max_members','200000','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(40,'channel_max_members','0','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(41,'apns_enabled','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(42,'apns_auth_key','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(43,'xiaomi_push_enabled','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(44,'max_voice_size','20','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(45,'require_invite_code','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(46,'require_phone_bind','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(47,'checkin_enabled','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(48,'custom_portal_icon_url','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(49,'xiaomi_package_name','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(50,'max_video_size','100','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(51,'new_user_follow_official','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(52,'invite_register_bind_only','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(53,'new_user_join_channel','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(54,'group_invite_require_friend','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(55,'member_only_create_group','true','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(56,'agora_app_certificate','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(57,'hms_enabled','false','bool','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(58,'oppo_app_key','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(59,'user_rate_limit','30','int','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(60,'apns_team_id','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(61,'hms_app_id','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(62,'discover_top_image_url','','string','','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL),(63,'api_txt_url','','string','api.txt 地址。管理后台只读，改动直接改本行。','2026-01-01 00:00:00','2026-01-01 00:00:00',NULL);
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `transactions`
--

LOCK TABLES `transactions` WRITE;
/*!40000 ALTER TABLE `transactions` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_chats`
--

LOCK TABLES `user_chats` WRITE;
/*!40000 ALTER TABLE `user_chats` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_checkin_stats`
--

LOCK TABLES `user_checkin_stats` WRITE;
/*!40000 ALTER TABLE `user_checkin_stats` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_checkins`
--

LOCK TABLES `user_checkins` WRITE;
/*!40000 ALTER TABLE `user_checkins` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_devices`
--

LOCK TABLES `user_devices` WRITE;
/*!40000 ALTER TABLE `user_devices` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_emoji_store_settings`
--

LOCK TABLES `user_emoji_store_settings` WRITE;
/*!40000 ALTER TABLE `user_emoji_store_settings` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_memberships`
--

LOCK TABLES `user_memberships` WRITE;
/*!40000 ALTER TABLE `user_memberships` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_privacy_settings`
--

LOCK TABLES `user_privacy_settings` WRITE;
/*!40000 ALTER TABLE `user_privacy_settings` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_push_settings`
--

LOCK TABLES `user_push_settings` WRITE;
/*!40000 ALTER TABLE `user_push_settings` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `user_sessions`
--

LOCK TABLES `user_sessions` WRITE;
/*!40000 ALTER TABLE `user_sessions` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `users`
--

LOCK TABLES `users` WRITE;
/*!40000 ALTER TABLE `users` DISABLE KEYS */;
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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `wallets`
--

LOCK TABLES `wallets` WRITE;
/*!40000 ALTER TABLE `wallets` DISABLE KEYS */;
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

-- Dump completed on 2026-07-09 19:43:34

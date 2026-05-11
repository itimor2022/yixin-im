-- 壹信 IM 数据库初始化脚本
-- MySQL 8.0+
-- 
-- 使用方法:
--   mysql -u root -p < init.sql
-- 或者在宝塔面板中导入此文件
--
-- 默认管理员账号: admin
-- 默认管理员密码: 123456
--

-- 创建数据库（如果使用宝塔面板创建数据库，可以注释掉这两行）
-- CREATE DATABASE IF NOT EXISTS gaoranim DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
-- USE gaoranim;

-- MySQL dump 10.13  Distrib 8.0.44, for macos15.7 (arm64)
--
-- Host: localhost    Database: gaoranim
-- ------------------------------------------------------
-- Server version	8.0.44

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `member_protection` tinyint(1) DEFAULT '0',
  `join_approval` tinyint(1) DEFAULT '0',
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_chats_uuid` (`uuid`),
  UNIQUE KEY `idx_chats_invite_link` (`invite_link`),
  KEY `idx_chats_deleted_at` (`deleted_at`),
  KEY `idx_chats_owner_id` (`owner_id`),
  KEY `idx_chats_username` (`username`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `sort` int DEFAULT '0',
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
  `status` tinyint DEFAULT '1',
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_contact` (`user_id`,`contact_user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `status` tinyint DEFAULT '1',
  `location` varchar(200) DEFAULT NULL,
  `created_at` datetime(3) DEFAULT NULL,
  `updated_at` datetime(3) DEFAULT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_moments_uuid` (`uuid`),
  KEY `idx_moments_user_id` (`user_id`),
  KEY `idx_moments_deleted_at` (`deleted_at`),
  CONSTRAINT `fk_moments_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_official_users_user_id` (`user_id`),
  UNIQUE KEY `idx_official_users_user_uuid` (`user_uuid`),
  KEY `idx_official_users_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `last_msg_id` bigint unsigned DEFAULT '0',
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
  PRIMARY KEY (`id`),
  KEY `idx_user_chats_target_id` (`target_id`),
  KEY `idx_user_chats_sort_time` (`sort_time`),
  KEY `idx_user_chat` (`user_id`,`chat_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `push_channel` varchar(20) DEFAULT NULL,
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
  KEY `idx_user_devices_user_id` (`user_id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_user_privacy_settings_user_id` (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

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
  `last_seen` datetime DEFAULT NULL,
  `created_at` datetime NOT NULL,
  `updated_at` datetime NOT NULL,
  `deleted_at` datetime(3) DEFAULT NULL,
  `password` varchar(100) NOT NULL,
  `emoji_avatar` varchar(100) DEFAULT NULL,
  `nickname_color` varchar(20) DEFAULT NULL,
  `ban_reason` varchar(500) DEFAULT NULL,
  `banned_at` datetime DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_users_uuid` (`uuid`),
  UNIQUE KEY `idx_users_username` (`username`),
  UNIQUE KEY `username` (`username`),
  UNIQUE KEY `idx_users_phone` (`phone`),
  KEY `idx_users_deleted_at` (`deleted_at`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- 插入默认超级管理员
-- 用户名: admin, 密码: 123456 (bcrypt加密)
--

INSERT INTO `admins` (`username`, `password`, `nickname`, `email`, `role`, `status`, `created_at`, `updated_at`)
VALUES ('admin', '$2a$10$8f.ZGUB06Cmytkj3QYH9t.ACflVH50.OG8esB09X6b2/eiVoLoIxq', '超级管理员', 'admin@gaoranim.com', 'super_admin', 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE `updated_at` = NOW();

-- 演示管理员（只能查看，不能编辑，无法获取敏感密钥）
-- 用户名: demo, 密码: demo123
INSERT INTO `admins` (`username`, `password`, `nickname`, `email`, `role`, `status`, `created_at`, `updated_at`)
VALUES ('demo', '$2a$10$oPg.CyASUzK8kyT6vLyFBuFtGFhGWc/Mm3bokT8zK.r4AO8pXVmlC', '演示管理员', 'demo@gaoranim.com', 'demo_admin', 1, NOW(), NOW())
ON DUPLICATE KEY UPDATE `updated_at` = NOW();

--
-- Dumping routines for database 'gaoranim'
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2026-01-28 16:30:20

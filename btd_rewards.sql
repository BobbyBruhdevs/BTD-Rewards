CREATE TABLE IF NOT EXISTS `btd_rewards_players` (
    `player_key` VARCHAR(128) NOT NULL,
    `steam_id` VARCHAR(64) NULL,
    `discord_id` VARCHAR(64) NULL,
    `player_name` VARCHAR(128) NOT NULL,
    `active_time` INT UNSIGNED NOT NULL DEFAULT 0,
    `rewards` LONGTEXT NOT NULL,
    `first_seen` BIGINT UNSIGNED NOT NULL,
    `last_seen` BIGINT UNSIGNED NOT NULL,
    PRIMARY KEY (`player_key`),
    INDEX `idx_btd_rewards_steam` (`steam_id`),
    INDEX `idx_btd_rewards_discord` (`discord_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `btd_rewards_codes` (
    `code` VARCHAR(64) NOT NULL,
    `player_key` VARCHAR(128) NOT NULL,
    `reward_index` INT UNSIGNED NOT NULL,
    `reward_name` VARCHAR(128) NOT NULL,
    `item_name` VARCHAR(64) NULL,
    `item_amount` INT UNSIGNED NULL,
    `expires_at` BIGINT UNSIGNED NOT NULL,
    `used` TINYINT UNSIGNED NOT NULL DEFAULT 0,
    `created_at` BIGINT UNSIGNED NOT NULL,
    `redeemed_at` BIGINT UNSIGNED NULL,
    PRIMARY KEY (`code`),
    INDEX `idx_btd_rewards_codes_player` (`player_key`),
    INDEX `idx_btd_rewards_codes_expiry` (`expires_at`),
    CONSTRAINT `fk_btd_rewards_codes_player`
        FOREIGN KEY (`player_key`) REFERENCES `btd_rewards_players` (`player_key`)
        ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

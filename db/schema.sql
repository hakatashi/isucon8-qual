CREATE TABLE IF NOT EXISTS users (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nickname    CHAR(128) NOT NULL,
    login_name  CHAR(128) NOT NULL,
    pass_hash   CHAR(128) NOT NULL,
    UNIQUE KEY login_name_uniq (login_name)
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS events (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    title       CHAR(128)     NOT NULL,
    public_fg   TINYINT(1)       NOT NULL,
    closed_fg   TINYINT(1)       NOT NULL,
    price       INTEGER UNSIGNED NOT NULL
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sheetstates (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    event_id    INTEGER UNSIGNED NOT NULL,
    sheet_id    INTEGER UNSIGNED NOT NULL,
    user_id     INTEGER UNSIGNED NOT NULL,
    reserved_at DATETIME(6)      NOT NULL,
    UNIQUE KEY event_sheet_id_uniq (event_id, sheet_id),
    INDEX `event_id_idx` (`event_id`),
    INDEX `sheet_id_idx` (`sheet_id`),
    INDEX `user_id_idx` (`user_id`),
    INDEX `reserved_at_idx` (`reserved_at`)
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sheetcounts (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    event_id    INTEGER UNSIGNED NOT NULL,
    `rank`      CHAR(4)     NOT NULL,
    count       INTEGER UNSIGNED NOT NULL,
    UNIQUE KEY event_id_rank_uniq (event_id, `rank`),
    INDEX `event_id_idx` (`event_id`),
    INDEX `rank_idx` (`rank`),
    INDEX `count_idx` (`count`)
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS sheets (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    `rank`      CHAR(4)     NOT NULL,
    num         INTEGER UNSIGNED NOT NULL,
    price       INTEGER UNSIGNED NOT NULL,
    UNIQUE KEY rank_num_uniq (`rank`, num),
    INDEX `rank_idx` (`rank`)
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS reservations (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    event_id    INTEGER UNSIGNED NOT NULL,
    sheet_id    INTEGER UNSIGNED NOT NULL,
    user_id     INTEGER UNSIGNED NOT NULL,
    reserved_at DATETIME(6)      NOT NULL,
    canceled_at DATETIME(6)      DEFAULT NULL,
    updated_at  DATETIME(6)      DEFAULT NULL,
    KEY event_id_and_sheet_id_idx (event_id, sheet_id),
    INDEX `sheet_id_idx` (sheet_id),
    INDEX `event_id_idx` (event_id),
    INDEX `reserved_at_idx` (reserved_at),
    INDEX `canceled_at_idx` (canceled_at),
    INDEX `updated_at_idx` (updated_at)
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS administrators (
    id          INTEGER UNSIGNED PRIMARY KEY AUTO_INCREMENT,
    nickname    CHAR(128) NOT NULL,
    login_name  CHAR(128) NOT NULL,
    pass_hash   CHAR(128) NOT NULL,
    UNIQUE KEY login_name_uniq (login_name)
) ENGINE=MEMORY DEFAULT CHARSET=utf8mb4;

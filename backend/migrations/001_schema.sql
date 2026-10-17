-- 001_schema.sql: every table from the "Data model" in docs/ARCHITECTURE.md.
-- Applied once by backend/migrate.py (which creates the database first).
--
-- Status-like columns are VARCHAR, not ENUM, so the contract in docs/API.md
-- can grow without a migration. The allowed values live in the API layer:
--   listings.category     tops, bottoms, outerwear, dresses, shoes, accessories, bags
--   listings.`condition`  new, like_new, good, worn
--   listings.share_type   swap, free, donate
--   listings.status       active, pending, completed, hidden
--   photos.kind           front, back, label, other, avatar
--   requests.status       pending, accepted, declined, completed, cancelled
--   notifications.type    request_received, request_accepted, request_declined,
--                         new_message, badge_earned
-- Timestamps are DATETIME in the server's time zone (UTC on HeatWave).

CREATE TABLE IF NOT EXISTS campuses (
  id            INT UNSIGNED NOT NULL AUTO_INCREMENT,
  name          VARCHAR(120) NOT NULL,
  email_domain  VARCHAR(120) NOT NULL,
  created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_campuses_email_domain (email_domain)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- avatar_photo_id has no foreign key: photos.owner_id already points at users,
-- and a cycle would make inserts and the seed reset awkward. The API checks it.
CREATE TABLE IF NOT EXISTS users (
  id               INT UNSIGNED NOT NULL AUTO_INCREMENT,
  campus_id        INT UNSIGNED NOT NULL,
  email            VARCHAR(255) NOT NULL,
  name             VARCHAR(80)  NULL,
  dorm             VARCHAR(80)  NULL,
  class_year       SMALLINT UNSIGNED NULL,
  size_top         VARCHAR(16)  NULL,
  size_bottom      VARCHAR(16)  NULL,
  size_shoe        VARCHAR(16)  NULL,
  avatar_photo_id  INT UNSIGNED NULL,
  created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_users_email (email),
  KEY ix_users_campus_dorm (campus_id, dorm),
  CONSTRAINT fk_users_campus FOREIGN KEY (campus_id) REFERENCES campuses (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS sessions (
  token       VARCHAR(64) NOT NULL,
  user_id     INT UNSIGNED NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (token),
  KEY ix_sessions_user (user_id),
  CONSTRAINT fk_sessions_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS meetup_spots (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  campus_id   INT UNSIGNED NOT NULL,
  name        VARCHAR(120) NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_meetup_spots_campus_name (campus_id, name),
  CONSTRAINT fk_meetup_spots_campus FOREIGN KEY (campus_id) REFERENCES campuses (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS listings (
  id              INT UNSIGNED NOT NULL AUTO_INCREMENT,
  owner_id        INT UNSIGNED NOT NULL,
  campus_id       INT UNSIGNED NOT NULL,
  title           VARCHAR(120) NOT NULL,
  category        VARCHAR(20)  NOT NULL,
  size            VARCHAR(20)  NULL,
  color           VARCHAR(60)  NULL,
  brand           VARCHAR(80)  NULL,
  `condition`     VARCHAR(20)  NOT NULL,
  description     TEXT         NULL,
  tags            JSON         NULL,
  share_type      VARCHAR(10)  NOT NULL,
  status          VARCHAR(12)  NOT NULL DEFAULT 'active',
  meetup_spot_id  INT UNSIGNED NULL,
  style_ideas     JSON         NULL,
  created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_listings_feed (campus_id, status, created_at),
  KEY ix_listings_feed_category (campus_id, status, category, created_at),
  KEY ix_listings_owner (owner_id, status, created_at),
  CONSTRAINT fk_listings_owner FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_listings_campus FOREIGN KEY (campus_id) REFERENCES campuses (id),
  CONSTRAINT fk_listings_meetup_spot FOREIGN KEY (meetup_spot_id) REFERENCES meetup_spots (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- listing_id stays NULL until the photo is attached to a posted listing.
CREATE TABLE IF NOT EXISTS photos (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  owner_id    INT UNSIGNED NOT NULL,
  listing_id  INT UNSIGNED NULL,
  kind        VARCHAR(10)  NOT NULL,
  path        VARCHAR(255) NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_photos_listing (listing_id, id),
  KEY ix_photos_owner (owner_id),
  CONSTRAINT fk_photos_owner FOREIGN KEY (owner_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_photos_listing FOREIGN KEY (listing_id) REFERENCES listings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- No unique (listing_id, requester_id): a requester may ask again after
-- cancelling. The API returns 409 if they already have an open request.
CREATE TABLE IF NOT EXISTS requests (
  id                      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  listing_id              INT UNSIGNED NOT NULL,
  requester_id            INT UNSIGNED NOT NULL,
  note                    VARCHAR(280) NULL,
  status                  VARCHAR(12)  NOT NULL DEFAULT 'pending',
  created_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at              DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  completed_at            DATETIME NULL,
  owner_last_read_id      INT UNSIGNED NOT NULL DEFAULT 0,
  requester_last_read_id  INT UNSIGNED NOT NULL DEFAULT 0,
  PRIMARY KEY (id),
  KEY ix_requests_listing (listing_id, status),
  KEY ix_requests_requester (requester_id, updated_at),
  KEY ix_requests_completed (status, completed_at),
  CONSTRAINT fk_requests_listing FOREIGN KEY (listing_id) REFERENCES listings (id) ON DELETE CASCADE,
  CONSTRAINT fk_requests_requester FOREIGN KEY (requester_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS messages (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  request_id  INT UNSIGNED NOT NULL,
  sender_id   INT UNSIGNED NOT NULL,
  body        VARCHAR(1000) NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_messages_request (request_id, id),
  CONSTRAINT fk_messages_request FOREIGN KEY (request_id) REFERENCES requests (id) ON DELETE CASCADE,
  CONSTRAINT fk_messages_sender FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS saves (
  user_id     INT UNSIGNED NOT NULL,
  listing_id  INT UNSIGNED NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, listing_id),
  KEY ix_saves_listing (listing_id),
  CONSTRAINT fk_saves_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_saves_listing FOREIGN KEY (listing_id) REFERENCES listings (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS reports (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  listing_id   INT UNSIGNED NOT NULL,
  reporter_id  INT UNSIGNED NOT NULL,
  reason       VARCHAR(200) NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_reports_listing_reporter (listing_id, reporter_id),
  KEY ix_reports_reporter (reporter_id),
  CONSTRAINT fk_reports_listing FOREIGN KEY (listing_id) REFERENCES listings (id) ON DELETE CASCADE,
  CONSTRAINT fk_reports_reporter FOREIGN KEY (reporter_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS notifications (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  user_id     INT UNSIGNED NOT NULL,
  type        VARCHAR(30)  NOT NULL,
  title       VARCHAR(160) NOT NULL,
  body        VARCHAR(500) NULL,
  request_id  INT UNSIGNED NULL,
  listing_id  INT UNSIGNED NULL,
  read_at     DATETIME NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_notifications_user_read (user_id, read_at),
  KEY ix_notifications_user_id (user_id, id),
  CONSTRAINT fk_notifications_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
  CONSTRAINT fk_notifications_request FOREIGN KEY (request_id) REFERENCES requests (id) ON DELETE SET NULL,
  CONSTRAINT fk_notifications_listing FOREIGN KEY (listing_id) REFERENCES listings (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- badge_id is a string key like 'first_swap' (see GET /me/badges).
CREATE TABLE IF NOT EXISTS user_badges (
  user_id     INT UNSIGNED NOT NULL,
  badge_id    VARCHAR(40)  NOT NULL,
  earned_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (user_id, badge_id),
  CONSTRAINT fk_user_badges_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

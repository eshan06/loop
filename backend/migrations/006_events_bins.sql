-- 006_events_bins.sql: campus events (Swap Day tab, I-29) and donation bins plus
-- meetup spot coordinates (campus map, I-28). S-27. Coordinates are WGS84 degrees;
-- DECIMAL(9,6) is about 10 cm of precision. Times are UTC like every other DATETIME.

CREATE TABLE IF NOT EXISTS events (
  id             INT UNSIGNED NOT NULL AUTO_INCREMENT,
  campus_id      INT UNSIGNED NOT NULL,
  title          VARCHAR(120) NOT NULL,
  description    VARCHAR(2000) NULL,
  kind           VARCHAR(30)  NOT NULL,
  starts_at      DATETIME NOT NULL,
  ends_at        DATETIME NOT NULL,
  location_name  VARCHAR(120) NOT NULL,
  lat            DECIMAL(9,6) NULL,
  lng            DECIMAL(9,6) NULL,
  created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_events_campus_ends (campus_id, ends_at),
  CONSTRAINT fk_events_campus FOREIGN KEY (campus_id) REFERENCES campuses (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS donation_bins (
  id           INT UNSIGNED NOT NULL AUTO_INCREMENT,
  campus_id    INT UNSIGNED NOT NULL,
  name         VARCHAR(120) NOT NULL,
  description  VARCHAR(500) NULL,
  accepts      VARCHAR(200) NULL,
  hours        VARCHAR(80)  NULL,
  lat          DECIMAL(9,6) NOT NULL,
  lng          DECIMAL(9,6) NOT NULL,
  created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  KEY ix_donation_bins_campus (campus_id),
  CONSTRAINT fk_donation_bins_campus FOREIGN KEY (campus_id) REFERENCES campuses (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- Last, as one statement, so a rerun after a failure above doesn't trip on it.
-- NULL for spots nobody has placed on the map (every new campus's defaults).
ALTER TABLE meetup_spots
  ADD COLUMN lat DECIMAL(9,6) NULL AFTER name,
  ADD COLUMN lng DECIMAL(9,6) NULL AFTER lat;

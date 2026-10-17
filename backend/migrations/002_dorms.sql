-- 002_dorms.sql: dorm names per campus, for GET /dorms (contract v1).
-- users.dorm stays a plain string; PATCH /me checks it against this list
-- when the campus has one, so the dorm leaderboard groups cleanly.
-- Rows come from the seed script (S-15).

CREATE TABLE IF NOT EXISTS dorms (
  id          INT UNSIGNED NOT NULL AUTO_INCREMENT,
  campus_id   INT UNSIGNED NOT NULL,
  name        VARCHAR(80)  NOT NULL,
  created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (id),
  UNIQUE KEY uq_dorms_campus_name (campus_id, name),
  CONSTRAINT fk_dorms_campus FOREIGN KEY (campus_id) REFERENCES campuses (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

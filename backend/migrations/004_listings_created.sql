-- 004_listings_created.sql: how many listings each user has ever created (S-22).
-- The Closet Cleanout badge counts listings "since deleted or completed"
-- (docs/API.md GET /me/badges), and DELETE /listings/{id} removes the row, so the
-- count can't come from the listings table alone. POST /listings adds 1; the seed
-- sets it for the demo accounts. Backfilled from the listings that exist today.

ALTER TABLE users ADD COLUMN listings_created INT UNSIGNED NOT NULL DEFAULT 0 AFTER avatar_photo_id;

UPDATE users u
  SET u.listings_created = (SELECT COUNT(*) FROM listings l WHERE l.owner_id = u.id);

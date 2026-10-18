-- 005_condition_note.sql: one short wear observation from the vision model or the
-- owner, like "light fading at the cuffs" (S-28, IOS-3). Nullable: most listings
-- have none, and a "new" item never needs one. POST/PATCH /listings cap it at 140.

ALTER TABLE listings ADD COLUMN condition_note VARCHAR(140) NULL AFTER `condition`;

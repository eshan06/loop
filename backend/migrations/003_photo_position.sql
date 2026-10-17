-- 003_photo_position.sql: keep a listing's photos in the order they were attached.
-- POST/PATCH /listings set position 0..4 from the order of photo_ids, so a PATCH
-- can reorder photos (docs/API.md: "replaces the listing's photos with that
-- list, in that order"). NULL until the photo is attached to a listing.

ALTER TABLE photos ADD COLUMN position SMALLINT UNSIGNED NULL AFTER listing_id;

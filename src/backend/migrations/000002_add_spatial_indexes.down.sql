-- Remove GiST spatial index from tags table location column
-- Used for optimizing tag location queries within 50-meter radius
DROP INDEX IF EXISTS tags_location_gist_idx;

-- Remove GiST spatial index from profiles table last_location column
-- Used for optimizing user location queries and proximity detection
DROP INDEX IF EXISTS profiles_location_gist_idx;

-- Remove B-tree index from tags table expiration column
-- Used for efficient tag expiration queries and cleanup
DROP INDEX IF EXISTS tags_expiration_btree_idx;

-- Remove B-tree index from tags table visibility_radius column
-- Used for filtering tags based on their visibility radius settings
DROP INDEX IF EXISTS tags_visibility_btree_idx;
-- Drop trigger first to avoid orphaned triggers
DROP TRIGGER IF EXISTS status_timestamp ON users;

-- Drop function after trigger since trigger depends on it
DROP FUNCTION IF EXISTS update_status_timestamp();

-- Drop index before removing column to maintain valid index state
DROP INDEX IF EXISTS users_status_points_idx;

-- Drop status tracking columns after removing dependent objects
ALTER TABLE users DROP COLUMN IF EXISTS status_updated_at;
ALTER TABLE users DROP COLUMN IF EXISTS status_points;
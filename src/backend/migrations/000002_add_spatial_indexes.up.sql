-- Enable PostGIS extension for spatial functionality
CREATE EXTENSION IF NOT EXISTS postgis;

-- Create GIST spatial index on profiles table for user location queries
-- Optimizes queries within 50m radius with ±1cm precision
CREATE INDEX IF NOT EXISTS idx_profiles_location_gist 
ON profiles USING GIST (last_location);

-- Create GIST spatial index on tags table for tag location queries
-- Supports efficient spatial queries from 0.5m to 50m range
CREATE INDEX IF NOT EXISTS idx_tags_location_gist 
ON tags USING GIST (location);

-- Create function to update timestamp when location changes
-- Used for monitoring spatial query performance
CREATE OR REPLACE FUNCTION update_location_timestamp()
RETURNS trigger AS $$
BEGIN
    -- Only update timestamp if location actually changed
    IF OLD.last_location IS DISTINCT FROM NEW.last_location THEN
        NEW.last_updated = CURRENT_TIMESTAMP;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update timestamp on location change
CREATE TRIGGER trigger_location_update
    BEFORE UPDATE OF last_location
    ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_location_timestamp();

-- Add statistics gathering for spatial columns to help query planner
ANALYZE profiles (last_location);
ANALYZE tags (location);

-- Set specific storage parameters for spatial indexes to optimize for our use case
ALTER INDEX idx_profiles_location_gist SET (fillfactor = 90);
ALTER INDEX idx_tags_location_gist SET (fillfactor = 90);

-- Create index on timestamp columns to help with performance monitoring queries
CREATE INDEX IF NOT EXISTS idx_profiles_last_updated 
ON profiles (last_updated);

-- Add constraint to ensure locations are within valid range (50m radius)
ALTER TABLE profiles ADD CONSTRAINT check_location_range
    CHECK (ST_DWithin(last_location, ST_SetSRID(ST_MakePoint(0,0), 4326), 50));

ALTER TABLE tags ADD CONSTRAINT check_tag_location_range
    CHECK (ST_DWithin(location, ST_SetSRID(ST_MakePoint(0,0), 4326), 50));

-- Add constraint for minimum precision (±1cm)
ALTER TABLE profiles ADD CONSTRAINT check_location_precision
    CHECK (ST_NPoints(last_location::geometry) >= 2);

ALTER TABLE tags ADD CONSTRAINT check_tag_location_precision
    CHECK (ST_NPoints(location::geometry) >= 2);
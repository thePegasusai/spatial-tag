-- Create enum for user status levels
CREATE TYPE user_status_level AS ENUM ('REGULAR', 'ELITE', 'RARE');

-- Alter profiles table to add status tracking columns
ALTER TABLE profiles 
    ALTER COLUMN status_level TYPE user_status_level 
    USING status_level::user_status_level,
    ALTER COLUMN status_level SET NOT NULL,
    ALTER COLUMN status_level SET DEFAULT 'REGULAR',
    ADD COLUMN status_points integer NOT NULL DEFAULT 0,
    ADD COLUMN weekly_points integer NOT NULL DEFAULT 0,
    ADD COLUMN points_updated_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Create indexes for performance optimization
CREATE INDEX idx_profiles_status_points ON profiles (status_points);
CREATE INDEX idx_profiles_weekly_points ON profiles (weekly_points);

-- Create function to update user status based on weekly points
CREATE OR REPLACE FUNCTION update_user_status()
RETURNS trigger AS $$
BEGIN
    -- Update status level based on weekly points thresholds
    IF NEW.weekly_points >= 1000 THEN
        NEW.status_level = 'RARE';
    ELSIF NEW.weekly_points >= 500 THEN
        NEW.status_level = 'ELITE';
    ELSE
        NEW.status_level = 'REGULAR';
    END IF;
    
    -- Update points_updated_at timestamp
    NEW.points_updated_at = CURRENT_TIMESTAMP;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for automatic status updates
CREATE TRIGGER trigger_status_update
    BEFORE UPDATE OF weekly_points
    ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION update_user_status();

-- Create function to reset weekly points
CREATE OR REPLACE FUNCTION reset_weekly_points()
RETURNS void AS $$
BEGIN
    -- Add weekly points to total status points before resetting
    UPDATE profiles 
    SET status_points = status_points + weekly_points,
        weekly_points = 0,
        points_updated_at = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Create scheduled job for weekly points reset
SELECT cron.schedule('0 0 * * 0', $$SELECT reset_weekly_points()$$);

-- Grant necessary permissions
GRANT EXECUTE ON FUNCTION update_user_status() TO spatial_tag_app;
GRANT EXECUTE ON FUNCTION reset_weekly_points() TO spatial_tag_app;
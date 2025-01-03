-- Drop tables in reverse order of creation to maintain referential integrity
-- Starting with tables that have foreign key dependencies

-- Drop tag interactions junction table
DROP TABLE IF EXISTS tag_interactions CASCADE;

-- Drop wishlists table
DROP TABLE IF EXISTS wishlists CASCADE;

-- Drop connections table
DROP TABLE IF EXISTS connections CASCADE;

-- Drop tags table
DROP TABLE IF EXISTS tags CASCADE;

-- Drop profiles table
DROP TABLE IF EXISTS profiles CASCADE;

-- Drop users table
DROP TABLE IF EXISTS users CASCADE;

-- Drop custom enum types after their dependent tables
DROP TYPE IF EXISTS user_status;
DROP TYPE IF EXISTS connection_status;
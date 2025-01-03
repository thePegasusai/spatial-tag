-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "postgis";

-- Create updated_at timestamp trigger function
CREATE OR REPLACE FUNCTION set_updated_at_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    email VARCHAR(255) NOT NULL UNIQUE 
        CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'),
    password_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP WITH TIME ZONE
);

-- Create users email index
CREATE INDEX users_email_idx ON users (email);

-- Create users updated_at trigger
CREATE TRIGGER update_users_timestamp
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at_timestamp();

-- Create profiles table
CREATE TABLE profiles (
    user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
    status_level VARCHAR(50) NOT NULL DEFAULT 'basic'
        CHECK (status_level IN ('basic', 'elite', 'rare')),
    last_location GEOMETRY(Point, 4326)
        CHECK (ST_SRID(last_location) = 4326),
    preferences JSONB NOT NULL DEFAULT '{}'::jsonb,
    last_active TIMESTAMP WITH TIME ZONE,
    is_visible BOOLEAN NOT NULL DEFAULT true
);

-- Create profiles indexes
CREATE INDEX profiles_location_idx ON profiles USING GIST (last_location);
CREATE INDEX profiles_status_idx ON profiles (status_level);

-- Create connections table
CREATE TABLE connections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id_1 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    user_id_2 UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    connected_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status VARCHAR(50) NOT NULL
        CHECK (status IN ('pending', 'connected', 'blocked')),
    CONSTRAINT user_order CHECK (user_id_1 < user_id_2),
    CONSTRAINT unique_connection UNIQUE (user_id_1, user_id_2)
);

-- Create connections indexes
CREATE INDEX connections_users_idx ON connections (user_id_1, user_id_2);
CREATE INDEX connections_status_idx ON connections (status);

-- Create wishlists table
CREATE TABLE wishlists (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    items JSONB NOT NULL DEFAULT '[]'::jsonb
        CHECK (jsonb_typeof(items) = 'array'),
    is_shared BOOLEAN NOT NULL DEFAULT false,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Create wishlists indexes
CREATE INDEX wishlists_user_idx ON wishlists (user_id);
CREATE INDEX wishlists_shared_idx ON wishlists (is_shared);

-- Create wishlists updated_at trigger
CREATE TRIGGER update_wishlists_timestamp
    BEFORE UPDATE ON wishlists
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at_timestamp();
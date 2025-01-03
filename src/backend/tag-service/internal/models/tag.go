package models

import (
    "errors"
    "math"
    "time"
    "go.mongodb.org/mongo-driver/bson/primitive" // v1.11.0
)

// Tag visibility constants
const (
    TagVisibilityUnspecified = 0
    TagVisibilityPublic      = 1
    TagVisibilityPrivate     = 2
    TagVisibilityEliteOnly   = 3
)

// Tag status constants
const (
    TagStatusUnspecified = 0
    TagStatusActive      = 1
    TagStatusExpired     = 2
    TagStatusDeleted     = 3
)

// Tag constraints
const (
    MaxTagRadius     = 50.0
    MaxTagDensity    = 10
    MaxContentLength = 1000
    MaxMediaUrls     = 5
)

// Location represents a geographical point in 3D space
type Location struct {
    Latitude  float64 `bson:"latitude" json:"latitude"`
    Longitude float64 `bson:"longitude" json:"longitude"`
    Altitude  float64 `bson:"altitude" json:"altitude"`
    Geohash   string  `bson:"geohash" json:"geohash"`
}

// Validate ensures location coordinates are within acceptable ranges
func (l *Location) Validate() error {
    if l.Latitude < -90 || l.Latitude > 90 {
        return errors.New("latitude must be between -90 and 90 degrees")
    }
    if l.Longitude < -180 || l.Longitude > 180 {
        return errors.New("longitude must be between -180 and 180 degrees")
    }
    if l.Altitude < -1000 || l.Altitude > 10000 {
        return errors.New("altitude must be between -1000 and 10000 meters")
    }
    if l.Geohash == "" {
        return errors.New("geohash is required")
    }
    return nil
}

// ToGeoJSON converts location to GeoJSON format for MongoDB spatial queries
func (l *Location) ToGeoJSON() map[string]interface{} {
    return map[string]interface{}{
        "type": "Point",
        "coordinates": []float64{
            l.Longitude, // GeoJSON specifies longitude first
            l.Latitude,
            l.Altitude,
        },
    }
}

// Tag represents a spatial digital marker with enhanced features
type Tag struct {
    ID              primitive.ObjectID     `bson:"_id,omitempty" json:"id"`
    CreatorID       string                `bson:"creator_id" json:"creator_id"`
    Location        Location              `bson:"location" json:"location"`
    Content         string                `bson:"content" json:"content"`
    MediaURLs       []string              `bson:"media_urls" json:"media_urls"`
    Category        string                `bson:"category" json:"category"`
    CreatedAt       time.Time             `bson:"created_at" json:"created_at"`
    ExpiresAt       time.Time             `bson:"expires_at" json:"expires_at"`
    VisibilityRadius float64              `bson:"visibility_radius" json:"visibility_radius"`
    Visibility      int                   `bson:"visibility" json:"visibility"`
    Status          int                   `bson:"status" json:"status"`
    InteractionCount int                  `bson:"interaction_count" json:"interaction_count"`
    Metadata        map[string]interface{} `bson:"metadata" json:"metadata"`
}

// Validate performs comprehensive validation of tag data
func (t *Tag) Validate() error {
    if err := t.Location.Validate(); err != nil {
        return errors.New("invalid location: " + err.Error())
    }

    if len(t.Content) > MaxContentLength {
        return errors.New("content exceeds maximum length")
    }

    if len(t.MediaURLs) > MaxMediaUrls {
        return errors.New("too many media URLs")
    }

    if t.VisibilityRadius <= 0 || t.VisibilityRadius > MaxTagRadius {
        return errors.New("visibility radius must be between 0 and MaxTagRadius")
    }

    if t.ExpiresAt.Before(time.Now()) {
        return errors.New("expiration time must be in the future")
    }

    if t.CreatorID == "" {
        return errors.New("creator ID is required")
    }

    if t.Visibility < TagVisibilityUnspecified || t.Visibility > TagVisibilityEliteOnly {
        return errors.New("invalid visibility level")
    }

    return nil
}

// IsExpired checks if the tag has expired
func (t *Tag) IsExpired() bool {
    return time.Now().After(t.ExpiresAt)
}

// IsVisible checks if tag is visible to a user based on status level and distance
func (t *Tag) IsVisible(userStatusLevel string, userLocation Location) bool {
    if t.Status != TagStatusActive {
        return false
    }

    // Check visibility level restrictions
    if t.Visibility == TagVisibilityEliteOnly && userStatusLevel != "elite" {
        return false
    }

    // Calculate distance between user and tag
    distance := calculateDistance(t.Location, userLocation)
    return distance <= t.VisibilityRadius
}

// calculateDistance calculates the 3D distance between two locations
func calculateDistance(loc1, loc2 Location) float64 {
    const earthRadius = 6371000 // Earth's radius in meters

    lat1 := loc1.Latitude * math.Pi / 180
    lat2 := loc2.Latitude * math.Pi / 180
    lon1 := loc1.Longitude * math.Pi / 180
    lon2 := loc2.Longitude * math.Pi / 180

    dlat := lat2 - lat1
    dlon := lon2 - lon1

    a := math.Sin(dlat/2)*math.Sin(dlat/2) +
        math.Cos(lat1)*math.Cos(lat2)*
            math.Sin(dlon/2)*math.Sin(dlon/2)
    c := 2 * math.Atan2(math.Sqrt(a), math.Sqrt(1-a))
    
    // Calculate surface distance
    surfaceDistance := earthRadius * c

    // Include altitude difference using Pythagorean theorem
    altitudeDiff := loc2.Altitude - loc1.Altitude
    return math.Sqrt(math.Pow(surfaceDistance, 2) + math.Pow(altitudeDiff, 2))
}
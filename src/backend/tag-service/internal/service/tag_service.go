package service

import (
    "context"
    "errors"
    "fmt"
    "time"

    "github.com/go-redis/redis/v8" // v8.11.5
    "github.com/prometheus/client_golang/prometheus" // v1.16.0
    "go.mongodb.org/mongo-driver/bson/primitive" // v1.11.0
    "google.golang.org/grpc/codes" // v1.1.0
    "google.golang.org/grpc/status" // v1.1.0

    "../models"
    "../repository"
)

const (
    defaultTagExpirationHours = 24
    maxVisibilityRadius      = 50.0
    minVisibilityRadius      = 1.0
    defaultCacheTTL         = 300 // 5 minutes
    maxBatchSize            = 100
)

// Metrics collectors
var (
    tagOperationDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "tag_service_operation_duration_seconds",
            Help: "Duration of tag service operations",
            Buckets: prometheus.ExponentialBuckets(0.01, 2, 10),
        },
        []string{"operation"},
    )

    tagOperationCounter = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "tag_service_operations_total",
            Help: "Total number of tag service operations",
        },
        []string{"operation", "status"},
    )
)

// TagService implements tag management operations with caching and monitoring
type TagService struct {
    repo              *repository.MongoRepository
    cache             *redis.Client
    operationCounter  *prometheus.CounterVec
    operationLatency  *prometheus.HistogramVec
}

// NewTagService creates a new TagService instance
func NewTagService(repo *repository.MongoRepository, cache *redis.Client) (*TagService, error) {
    if repo == nil {
        return nil, errors.New("repository is required")
    }
    if cache == nil {
        return nil, errors.New("cache client is required")
    }

    // Register metrics
    prometheus.MustRegister(tagOperationDuration, tagOperationCounter)

    return &TagService{
        repo:             repo,
        cache:            cache,
        operationCounter: tagOperationCounter,
        operationLatency: tagOperationDuration,
    }, nil
}

// CreateTag creates a new tag with validation and monitoring
func (s *TagService) CreateTag(ctx context.Context, tag *models.Tag) (*models.Tag, error) {
    timer := prometheus.NewTimer(s.operationLatency.WithLabelValues("create_tag"))
    defer timer.ObserveDuration()

    // Validate tag data
    if err := tag.Validate(); err != nil {
        s.operationCounter.WithLabelValues("create_tag", "validation_failed").Inc()
        return nil, status.Errorf(codes.InvalidArgument, "invalid tag data: %v", err)
    }

    // Set default values if not provided
    if tag.ExpiresAt.IsZero() {
        tag.ExpiresAt = time.Now().Add(defaultTagExpirationHours * time.Hour)
    }
    if tag.VisibilityRadius == 0 {
        tag.VisibilityRadius = maxVisibilityRadius
    }

    // Create tag in repository
    createdTag, err := s.repo.CreateTag(ctx, tag)
    if err != nil {
        s.operationCounter.WithLabelValues("create_tag", "failed").Inc()
        return nil, status.Errorf(codes.Internal, "failed to create tag: %v", err)
    }

    // Cache the created tag
    cacheKey := fmt.Sprintf("tag:%s", createdTag.ID.Hex())
    if err := s.cache.Set(ctx, cacheKey, createdTag, defaultCacheTTL*time.Second).Err(); err != nil {
        // Log cache error but don't fail the operation
        s.operationCounter.WithLabelValues("create_tag_cache", "failed").Inc()
    }

    s.operationCounter.WithLabelValues("create_tag", "success").Inc()
    return createdTag, nil
}

// GetNearbyTags retrieves tags near a location with caching
func (s *TagService) GetNearbyTags(ctx context.Context, location models.Location, radius float64, userStatusLevel string) ([]*models.Tag, error) {
    timer := prometheus.NewTimer(s.operationLatency.WithLabelValues("get_nearby_tags"))
    defer timer.ObserveDuration()

    // Validate parameters
    if err := location.Validate(); err != nil {
        s.operationCounter.WithLabelValues("get_nearby_tags", "validation_failed").Inc()
        return nil, status.Errorf(codes.InvalidArgument, "invalid location: %v", err)
    }
    if radius <= 0 || radius > maxVisibilityRadius {
        s.operationCounter.WithLabelValues("get_nearby_tags", "validation_failed").Inc()
        return nil, status.Errorf(codes.InvalidArgument, "radius must be between 0 and %v meters", maxVisibilityRadius)
    }

    // Try to get from cache first
    cacheKey := fmt.Sprintf("nearby:%f:%f:%f:%f", location.Latitude, location.Longitude, radius, location.Altitude)
    var tags []*models.Tag
    if err := s.cache.Get(ctx, cacheKey).Scan(&tags); err == nil {
        s.operationCounter.WithLabelValues("get_nearby_tags_cache", "hit").Inc()
        return tags, nil
    }

    // Get tags from repository
    tags, err := s.repo.GetNearbyTags(ctx, location, radius, userStatusLevel)
    if err != nil {
        s.operationCounter.WithLabelValues("get_nearby_tags", "failed").Inc()
        return nil, status.Errorf(codes.Internal, "failed to get nearby tags: %v", err)
    }

    // Cache the results
    if err := s.cache.Set(ctx, cacheKey, tags, defaultCacheTTL*time.Second).Err(); err != nil {
        s.operationCounter.WithLabelValues("get_nearby_tags_cache", "failed").Inc()
    }

    s.operationCounter.WithLabelValues("get_nearby_tags", "success").Inc()
    return tags, nil
}

// UpdateTag updates an existing tag with validation
func (s *TagService) UpdateTag(ctx context.Context, tag *models.Tag) (*models.Tag, error) {
    timer := prometheus.NewTimer(s.operationLatency.WithLabelValues("update_tag"))
    defer timer.ObserveDuration()

    // Validate tag data
    if err := tag.Validate(); err != nil {
        s.operationCounter.WithLabelValues("update_tag", "validation_failed").Inc()
        return nil, status.Errorf(codes.InvalidArgument, "invalid tag data: %v", err)
    }

    // Update tag in repository
    updatedTag, err := s.repo.UpdateTag(ctx, tag)
    if err != nil {
        s.operationCounter.WithLabelValues("update_tag", "failed").Inc()
        return nil, status.Errorf(codes.Internal, "failed to update tag: %v", err)
    }

    // Update cache
    cacheKey := fmt.Sprintf("tag:%s", updatedTag.ID.Hex())
    if err := s.cache.Set(ctx, cacheKey, updatedTag, defaultCacheTTL*time.Second).Err(); err != nil {
        s.operationCounter.WithLabelValues("update_tag_cache", "failed").Inc()
    }

    s.operationCounter.WithLabelValues("update_tag", "success").Inc()
    return updatedTag, nil
}

// DeleteTag removes a tag and its cache entries
func (s *TagService) DeleteTag(ctx context.Context, id primitive.ObjectID) error {
    timer := prometheus.NewTimer(s.operationLatency.WithLabelValues("delete_tag"))
    defer timer.ObserveDuration()

    // Delete from repository
    if err := s.repo.DeleteTag(ctx, id); err != nil {
        s.operationCounter.WithLabelValues("delete_tag", "failed").Inc()
        return status.Errorf(codes.Internal, "failed to delete tag: %v", err)
    }

    // Remove from cache
    cacheKey := fmt.Sprintf("tag:%s", id.Hex())
    if err := s.cache.Del(ctx, cacheKey).Err(); err != nil {
        s.operationCounter.WithLabelValues("delete_tag_cache", "failed").Inc()
    }

    s.operationCounter.WithLabelValues("delete_tag", "success").Inc()
    return nil
}

// BatchCreateTags creates multiple tags efficiently
func (s *TagService) BatchCreateTags(ctx context.Context, tags []*models.Tag) ([]*models.Tag, error) {
    timer := prometheus.NewTimer(s.operationLatency.WithLabelValues("batch_create_tags"))
    defer timer.ObserveDuration()

    if len(tags) > maxBatchSize {
        s.operationCounter.WithLabelValues("batch_create_tags", "validation_failed").Inc()
        return nil, status.Errorf(codes.InvalidArgument, "batch size exceeds maximum of %d", maxBatchSize)
    }

    // Validate all tags
    for _, tag := range tags {
        if err := tag.Validate(); err != nil {
            s.operationCounter.WithLabelValues("batch_create_tags", "validation_failed").Inc()
            return nil, status.Errorf(codes.InvalidArgument, "invalid tag data: %v", err)
        }
    }

    // Create tags in repository
    createdTags, err := s.repo.BatchCreateTags(ctx, tags)
    if err != nil {
        s.operationCounter.WithLabelValues("batch_create_tags", "failed").Inc()
        return nil, status.Errorf(codes.Internal, "failed to create tags: %v", err)
    }

    // Cache all created tags
    pipe := s.cache.Pipeline()
    for _, tag := range createdTags {
        cacheKey := fmt.Sprintf("tag:%s", tag.ID.Hex())
        pipe.Set(ctx, cacheKey, tag, defaultCacheTTL*time.Second)
    }
    if _, err := pipe.Exec(ctx); err != nil {
        s.operationCounter.WithLabelValues("batch_create_tags_cache", "failed").Inc()
    }

    s.operationCounter.WithLabelValues("batch_create_tags", "success").Inc()
    return createdTags, nil
}
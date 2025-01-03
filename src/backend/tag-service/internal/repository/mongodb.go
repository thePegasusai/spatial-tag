package repository

import (
    "context"
    "errors"
    "sync"
    "time"

    "go.mongodb.org/mongo-driver/mongo" // v1.11.0
    "go.mongodb.org/mongo-driver/bson" // v1.11.0
    "go.mongodb.org/mongo-driver/bson/primitive" // v1.11.0
    "go.mongodb.org/mongo-driver/mongo/options" // v1.11.0
    "github.com/opentracing/opentracing-go" // v1.2.0
    "github.com/prometheus/client_golang/prometheus" // v1.11.0

    "../models"
    "../config"
)

const (
    locationIndexName    = "location_2dsphere"
    expirationIndexName = "expires_at_1"
    defaultQueryTimeout = 10 * time.Second
    maxRetries         = 3
    batchSize         = 1000
)

// Metrics collectors
var (
    queryDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name: "tag_query_duration_seconds",
            Help: "Duration of tag queries in seconds",
            Buckets: prometheus.ExponentialBuckets(0.01, 2, 10),
        },
        []string{"operation"},
    )

    tagOperations = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "tag_operations_total",
            Help: "Total number of tag operations",
        },
        []string{"operation", "status"},
    )
)

// MongoRepository implements the tag repository interface using MongoDB
type MongoRepository struct {
    collection *mongo.Collection
    config     *config.Config
    bufferPool sync.Pool
}

// NewMongoRepository creates a new MongoDB repository instance
func NewMongoRepository(client *mongo.Client, cfg *config.Config) (*MongoRepository, error) {
    if client == nil {
        return nil, errors.New("mongodb client is required")
    }

    // Initialize repository
    repo := &MongoRepository{
        collection: client.Database(cfg.Mongo.Database).Collection(cfg.Mongo.Collection),
        config:     cfg,
        bufferPool: sync.Pool{
            New: func() interface{} {
                return make([]models.Tag, 0, batchSize)
            },
        },
    }

    // Register metrics
    prometheus.MustRegister(queryDuration, tagOperations)

    // Ensure indexes
    ctx, cancel := context.WithTimeout(context.Background(), cfg.Mongo.Timeout)
    defer cancel()

    if err := repo.ensureIndexes(ctx); err != nil {
        return nil, err
    }

    return repo, nil
}

// ensureIndexes creates required MongoDB indexes
func (r *MongoRepository) ensureIndexes(ctx context.Context) error {
    // Create 2dsphere index for spatial queries
    locationIndex := mongo.IndexModel{
        Keys: bson.D{{Key: "location", Value: "2dsphere"}},
        Options: options.Index().
            SetName(locationIndexName).
            SetBackground(true),
    }

    // Create compound index for expiration and status
    expirationIndex := mongo.IndexModel{
        Keys: bson.D{
            {Key: "expires_at", Value: 1},
            {Key: "status", Value: 1},
        },
        Options: options.Index().
            SetName(expirationIndexName).
            SetBackground(true),
    }

    // Create indexes
    _, err := r.collection.Indexes().CreateMany(ctx, []mongo.IndexModel{
        locationIndex,
        expirationIndex,
    })

    if err != nil {
        tagOperations.WithLabelValues("create_index", "failure").Inc()
        return err
    }

    tagOperations.WithLabelValues("create_index", "success").Inc()
    return nil
}

// GetNearbyTags retrieves tags near a given location with status filtering
func (r *MongoRepository) GetNearbyTags(ctx context.Context, location models.Location, radius float64, userStatusLevel string) ([]*models.Tag, error) {
    span, ctx := opentracing.StartSpanFromContext(ctx, "MongoRepository.GetNearbyTags")
    defer span.Finish()

    timer := prometheus.NewTimer(queryDuration.WithLabelValues("get_nearby"))
    defer timer.ObserveDuration()

    // Create aggregation pipeline
    pipeline := mongo.Pipeline{
        {{Key: "$geoNear", Value: bson.D{
            {Key: "near", Value: location.ToGeoJSON()},
            {Key: "distanceField", Value: "distance"},
            {Key: "maxDistance", Value: radius},
            {Key: "spherical", Value: true},
            {Key: "query", Value: bson.D{
                {Key: "status", Value: models.TagStatusActive},
                {Key: "expires_at", Value: bson.D{{Key: "$gt", Value: time.Now()}}},
                {Key: "$or", Value: []bson.D{
                    {{Key: "visibility", Value: models.TagVisibilityPublic}},
                    {{Key: "visibility", Value: models.TagVisibilityEliteOnly}, {Key: "user_status_level", Value: "elite"}},
                }},
            }},
        }}},
    }

    // Execute aggregation with timeout
    ctx, cancel := context.WithTimeout(ctx, defaultQueryTimeout)
    defer cancel()

    cursor, err := r.collection.Aggregate(ctx, pipeline)
    if err != nil {
        tagOperations.WithLabelValues("get_nearby", "failure").Inc()
        return nil, err
    }
    defer cursor.Close(ctx)

    // Process results using buffer pool
    results := r.bufferPool.Get().([]models.Tag)
    defer r.bufferPool.Put(results)

    if err := cursor.All(ctx, &results); err != nil {
        tagOperations.WithLabelValues("get_nearby", "failure").Inc()
        return nil, err
    }

    // Convert results to pointer slice
    tags := make([]*models.Tag, len(results))
    for i := range results {
        tags[i] = &results[i]
    }

    tagOperations.WithLabelValues("get_nearby", "success").Inc()
    return tags, nil
}

// CleanupExpiredTags removes expired tags in batches
func (r *MongoRepository) CleanupExpiredTags(ctx context.Context) error {
    span, ctx := opentracing.StartSpanFromContext(ctx, "MongoRepository.CleanupExpiredTags")
    defer span.Finish()

    timer := prometheus.NewTimer(queryDuration.WithLabelValues("cleanup"))
    defer timer.ObserveDuration()

    filter := bson.D{
        {Key: "expires_at", Value: bson.D{{Key: "$lt", Value: time.Now()}}},
        {Key: "status", Value: models.TagStatusActive},
    }

    opts := options.Find().
        SetBatchSize(batchSize).
        SetNoCursorTimeout(true)

    cursor, err := r.collection.Find(ctx, filter, opts)
    if err != nil {
        tagOperations.WithLabelValues("cleanup", "failure").Inc()
        return err
    }
    defer cursor.Close(ctx)

    var deleteCount int64
    for cursor.Next(ctx) {
        var tag models.Tag
        if err := cursor.Decode(&tag); err != nil {
            continue
        }

        _, err := r.collection.UpdateOne(ctx, 
            bson.D{{Key: "_id", Value: tag.ID}},
            bson.D{{Key: "$set", Value: bson.D{{Key: "status", Value: models.TagStatusExpired}}}},
        )
        if err != nil {
            continue
        }
        deleteCount++
    }

    tagOperations.WithLabelValues("cleanup", "success").
        Add(float64(deleteCount))

    return nil
}
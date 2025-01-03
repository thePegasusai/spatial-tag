package integration

import (
    "context"
    "fmt"
    "math/rand"
    "sync"
    "testing"
    "time"

    "github.com/stretchr/testify/require"
    "go.mongodb.org/mongo-driver/bson/primitive"
    "go.mongodb.org/mongo-driver/mongo"
    "go.mongodb.org/mongo-driver/mongo/options"

    "../../internal/models"
    "../../internal/service"
    "../../internal/config"
    "../../internal/repository"
)

const (
    testDBName         = "spatial_tag_test"
    testCollectionName = "tags_test"
    testTimeout       = time.Second * 30
    benchmarkTimeout  = time.Minute
)

var (
    testClient *mongo.Client
    testRepo   *repository.MongoRepository
    testSvc    *service.TagService
)

// TestMain handles test setup and teardown
func TestMain(m *testing.M) {
    ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
    defer cancel()

    // Initialize test MongoDB client
    var err error
    testClient, err = mongo.Connect(ctx, options.Client().ApplyURI("mongodb://localhost:27017"))
    if err != nil {
        panic(fmt.Sprintf("Failed to connect to test database: %v", err))
    }
    defer testClient.Disconnect(ctx)

    // Create test configuration
    cfg := &config.Config{
        Environment: config.EnvDevelopment,
        Mongo: config.MongoConfig{
            Database:   testDBName,
            Collection: testCollectionName,
            Timeout:    testTimeout,
        },
    }

    // Initialize repository and service
    testRepo, err = repository.NewMongoRepository(testClient, cfg)
    if err != nil {
        panic(fmt.Sprintf("Failed to create test repository: %v", err))
    }

    // Run tests
    code := m.Run()

    // Cleanup test database
    if err := testClient.Database(testDBName).Drop(ctx); err != nil {
        fmt.Printf("Failed to cleanup test database: %v\n", err)
    }

    os.Exit(code)
}

// TestCreateTagConcurrent tests concurrent tag creation
func TestCreateTagConcurrent(t *testing.T) {
    ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
    defer cancel()

    const numConcurrentTags = 100
    var wg sync.WaitGroup
    errChan := make(chan error, numConcurrentTags)

    // Create tags concurrently
    for i := 0; i < numConcurrentTags; i++ {
        wg.Add(1)
        go func(idx int) {
            defer wg.Done()

            tag := &models.Tag{
                CreatorID: fmt.Sprintf("user_%d", idx),
                Location: models.Location{
                    Latitude:  40.7128 + (rand.Float64() * 0.01),
                    Longitude: -74.0060 + (rand.Float64() * 0.01),
                    Altitude:  10.0,
                    Geohash:   "dr5r", // Example geohash
                },
                Content:          fmt.Sprintf("Test tag content %d", idx),
                CreatedAt:        time.Now(),
                ExpiresAt:        time.Now().Add(24 * time.Hour),
                VisibilityRadius: 50.0,
                Visibility:       models.TagVisibilityPublic,
                Status:          models.TagStatusActive,
            }

            _, err := testSvc.CreateTag(ctx, tag)
            if err != nil {
                errChan <- fmt.Errorf("failed to create tag %d: %v", idx, err)
            }
        }(i)
    }

    // Wait for all goroutines and check for errors
    wg.Wait()
    close(errChan)

    for err := range errChan {
        t.Error(err)
    }

    // Verify tag count
    count, err := testClient.Database(testDBName).Collection(testCollectionName).CountDocuments(ctx, bson.M{})
    require.NoError(t, err)
    require.Equal(t, int64(numConcurrentTags), count)
}

// TestTagVisibilityLevels tests tag visibility based on user status
func TestTagVisibilityLevels(t *testing.T) {
    ctx, cancel := context.WithTimeout(context.Background(), testTimeout)
    defer cancel()

    // Create test tags with different visibility levels
    testCases := []struct {
        name           string
        visibility    int
        userStatus    string
        shouldBeVisible bool
    }{
        {"Public tag visible to regular user", models.TagVisibilityPublic, "regular", true},
        {"Elite tag not visible to regular user", models.TagVisibilityEliteOnly, "regular", false},
        {"Elite tag visible to elite user", models.TagVisibilityEliteOnly, "elite", true},
        {"Public tag visible to elite user", models.TagVisibilityPublic, "elite", true},
    }

    baseLocation := models.Location{
        Latitude:  40.7128,
        Longitude: -74.0060,
        Altitude:  10.0,
        Geohash:   "dr5r",
    }

    for _, tc := range testCases {
        t.Run(tc.name, func(t *testing.T) {
            // Create test tag
            tag := &models.Tag{
                CreatorID:        "test_user",
                Location:         baseLocation,
                Content:         "Test content",
                CreatedAt:       time.Now(),
                ExpiresAt:       time.Now().Add(24 * time.Hour),
                VisibilityRadius: 50.0,
                Visibility:      tc.visibility,
                Status:         models.TagStatusActive,
            }

            createdTag, err := testSvc.CreateTag(ctx, tag)
            require.NoError(t, err)

            // Query tags with user status
            nearbyTags, err := testSvc.GetNearbyTags(ctx, baseLocation, 100.0, tc.userStatus)
            require.NoError(t, err)

            // Verify visibility
            found := false
            for _, nt := range nearbyTags {
                if nt.ID == createdTag.ID {
                    found = true
                    break
                }
            }
            require.Equal(t, tc.shouldBeVisible, found)
        })
    }
}

// BenchmarkNearbyTagQueries benchmarks spatial query performance
func BenchmarkNearbyTagQueries(b *testing.B) {
    ctx, cancel := context.WithTimeout(context.Background(), benchmarkTimeout)
    defer cancel()

    // Create test dataset
    const numTestTags = 10000
    baseLocation := models.Location{
        Latitude:  40.7128,
        Longitude: -74.0060,
        Altitude:  10.0,
        Geohash:   "dr5r",
    }

    // Create tags in a grid pattern
    for i := 0; i < numTestTags; i++ {
        tag := &models.Tag{
            CreatorID: fmt.Sprintf("bench_user_%d", i),
            Location: models.Location{
                Latitude:  baseLocation.Latitude + (float64(i/100) * 0.001),
                Longitude: baseLocation.Longitude + (float64(i%100) * 0.001),
                Altitude:  baseLocation.Altitude,
                Geohash:   baseLocation.Geohash,
            },
            Content:          fmt.Sprintf("Benchmark tag %d", i),
            CreatedAt:        time.Now(),
            ExpiresAt:        time.Now().Add(24 * time.Hour),
            VisibilityRadius: 50.0,
            Visibility:       models.TagVisibilityPublic,
            Status:          models.TagStatusActive,
        }
        _, err := testSvc.CreateTag(ctx, tag)
        require.NoError(b, err)
    }

    // Benchmark queries at different radiuses
    radiuses := []float64{50, 100, 500, 1000}
    for _, radius := range radiuses {
        b.Run(fmt.Sprintf("Radius_%vm", radius), func(b *testing.B) {
            for i := 0; i < b.N; i++ {
                _, err := testSvc.GetNearbyTags(ctx, baseLocation, radius, "regular")
                require.NoError(b, err)
            }
        })
    }
}
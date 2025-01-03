package tests

import (
    "context"
    "testing"
    "time"

    "github.com/stretchr/testify/assert"
    "github.com/stretchr/testify/mock"
    "github.com/stretchr/testify/require"
    "go.mongodb.org/mongo-driver/bson/primitive"

    "../../internal/models"
    "../../internal/service"
    "../../internal/repository"
)

// mockRepository implements repository.Repository interface for testing
type mockRepository struct {
    mock.Mock
}

func (m *mockRepository) CreateTag(ctx context.Context, tag *models.Tag) (*models.Tag, error) {
    args := m.Called(ctx, tag)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*models.Tag), args.Error(1)
}

func (m *mockRepository) GetNearbyTags(ctx context.Context, location models.Location, radius float64, userStatusLevel string) ([]*models.Tag, error) {
    args := m.Called(ctx, location, radius, userStatusLevel)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).([]*models.Tag), args.Error(1)
}

func (m *mockRepository) UpdateTag(ctx context.Context, tag *models.Tag) (*models.Tag, error) {
    args := m.Called(ctx, tag)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).(*models.Tag), args.Error(1)
}

func (m *mockRepository) DeleteTag(ctx context.Context, id primitive.ObjectID) error {
    args := m.Called(ctx, id)
    return args.Error(0)
}

func (m *mockRepository) BatchCreateTags(ctx context.Context, tags []*models.Tag) ([]*models.Tag, error) {
    args := m.Called(ctx, tags)
    if args.Get(0) == nil {
        return nil, args.Error(1)
    }
    return args.Get(0).([]*models.Tag), args.Error(1)
}

// Test setup helper
func setupTest(t *testing.T) (*mockRepository, service.TagService, context.Context) {
    mockRepo := new(mockRepository)
    tagService, err := service.NewTagService(mockRepo)
    require.NoError(t, err)
    
    ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
    t.Cleanup(cancel)
    
    return mockRepo, tagService, ctx
}

// Test tag service initialization
func TestNewTagService(t *testing.T) {
    t.Run("successful initialization", func(t *testing.T) {
        mockRepo := new(mockRepository)
        svc, err := service.NewTagService(mockRepo)
        require.NoError(t, err)
        assert.NotNil(t, svc)
    })

    t.Run("nil repository", func(t *testing.T) {
        svc, err := service.NewTagService(nil)
        assert.Error(t, err)
        assert.Nil(t, svc)
    })
}

// Test tag creation
func TestCreateTag(t *testing.T) {
    mockRepo, tagService, ctx := setupTest(t)

    t.Run("successful creation", func(t *testing.T) {
        tag := &models.Tag{
            CreatorID: "test-user-123",
            Location: models.Location{
                Latitude:  40.7128,
                Longitude: -74.0060,
                Altitude:  10.0,
                Geohash:   "dr5r9ydj",
            },
            Content:          "Test tag content",
            VisibilityRadius: 50.0,
            ExpiresAt:       time.Now().Add(24 * time.Hour),
            Visibility:      models.TagVisibilityPublic,
            Status:         models.TagStatusActive,
        }

        expectedTag := *tag
        expectedTag.ID = primitive.NewObjectID()

        mockRepo.On("CreateTag", ctx, tag).Return(&expectedTag, nil)

        createdTag, err := tagService.CreateTag(ctx, tag)
        require.NoError(t, err)
        assert.Equal(t, expectedTag.ID, createdTag.ID)
        assert.Equal(t, tag.CreatorID, createdTag.CreatorID)
        assert.Equal(t, tag.Location, createdTag.Location)
        mockRepo.AssertExpectations(t)
    })

    t.Run("validation error", func(t *testing.T) {
        invalidTag := &models.Tag{
            CreatorID: "", // Invalid: empty creator ID
            Location: models.Location{
                Latitude:  200, // Invalid: latitude > 90
                Longitude: -74.0060,
            },
        }

        _, err := tagService.CreateTag(ctx, invalidTag)
        assert.Error(t, err)
        mockRepo.AssertNotCalled(t, "CreateTag")
    })

    t.Run("duplicate tag error", func(t *testing.T) {
        tag := &models.Tag{
            CreatorID: "test-user-123",
            Location: models.Location{
                Latitude:  40.7128,
                Longitude: -74.0060,
                Altitude:  10.0,
                Geohash:   "dr5r9ydj",
            },
        }

        mockRepo.On("CreateTag", ctx, tag).Return(nil, repository.ErrDuplicateTag)

        _, err := tagService.CreateTag(ctx, tag)
        assert.Error(t, err)
        mockRepo.AssertExpectations(t)
    })
}

// Test nearby tags retrieval
func TestGetNearbyTags(t *testing.T) {
    mockRepo, tagService, ctx := setupTest(t)

    t.Run("successful retrieval", func(t *testing.T) {
        location := models.Location{
            Latitude:  40.7128,
            Longitude: -74.0060,
            Altitude:  10.0,
            Geohash:   "dr5r9ydj",
        }
        radius := 50.0
        userStatus := "Elite"

        expectedTags := []*models.Tag{
            {
                ID:        primitive.NewObjectID(),
                CreatorID: "user-1",
                Location:  location,
                Content:   "Nearby tag 1",
                Status:   models.TagStatusActive,
            },
            {
                ID:        primitive.NewObjectID(),
                CreatorID: "user-2",
                Location:  location,
                Content:   "Nearby tag 2",
                Status:   models.TagStatusActive,
            },
        }

        mockRepo.On("GetNearbyTags", ctx, location, radius, userStatus).Return(expectedTags, nil)

        tags, err := tagService.GetNearbyTags(ctx, location, radius, userStatus)
        require.NoError(t, err)
        assert.Len(t, tags, 2)
        assert.Equal(t, expectedTags, tags)
        mockRepo.AssertExpectations(t)
    })

    t.Run("invalid location", func(t *testing.T) {
        invalidLocation := models.Location{
            Latitude:  100, // Invalid: latitude > 90
            Longitude: -74.0060,
        }

        _, err := tagService.GetNearbyTags(ctx, invalidLocation, 50.0, "Elite")
        assert.Error(t, err)
        mockRepo.AssertNotCalled(t, "GetNearbyTags")
    })

    t.Run("invalid radius", func(t *testing.T) {
        location := models.Location{
            Latitude:  40.7128,
            Longitude: -74.0060,
            Geohash:   "dr5r9ydj",
        }

        _, err := tagService.GetNearbyTags(ctx, location, -1.0, "Elite")
        assert.Error(t, err)
        mockRepo.AssertNotCalled(t, "GetNearbyTags")
    })
}

// Test tag update
func TestUpdateTag(t *testing.T) {
    mockRepo, tagService, ctx := setupTest(t)

    t.Run("successful update", func(t *testing.T) {
        tag := &models.Tag{
            ID:        primitive.NewObjectID(),
            CreatorID: "test-user-123",
            Location: models.Location{
                Latitude:  40.7128,
                Longitude: -74.0060,
                Altitude:  10.0,
                Geohash:   "dr5r9ydj",
            },
            Content:          "Updated content",
            VisibilityRadius: 50.0,
            Status:         models.TagStatusActive,
        }

        mockRepo.On("UpdateTag", ctx, tag).Return(tag, nil)

        updatedTag, err := tagService.UpdateTag(ctx, tag)
        require.NoError(t, err)
        assert.Equal(t, tag.ID, updatedTag.ID)
        assert.Equal(t, tag.Content, updatedTag.Content)
        mockRepo.AssertExpectations(t)
    })

    t.Run("tag not found", func(t *testing.T) {
        tag := &models.Tag{
            ID: primitive.NewObjectID(),
        }

        mockRepo.On("UpdateTag", ctx, tag).Return(nil, service.ErrTagNotFound)

        _, err := tagService.UpdateTag(ctx, tag)
        assert.Error(t, err)
        assert.Equal(t, service.ErrTagNotFound, err)
        mockRepo.AssertExpectations(t)
    })
}

// Test tag deletion
func TestDeleteTag(t *testing.T) {
    mockRepo, tagService, ctx := setupTest(t)

    t.Run("successful deletion", func(t *testing.T) {
        id := primitive.NewObjectID()
        mockRepo.On("DeleteTag", ctx, id).Return(nil)

        err := tagService.DeleteTag(ctx, id)
        assert.NoError(t, err)
        mockRepo.AssertExpectations(t)
    })

    t.Run("tag not found", func(t *testing.T) {
        id := primitive.NewObjectID()
        mockRepo.On("DeleteTag", ctx, id).Return(service.ErrTagNotFound)

        err := tagService.DeleteTag(ctx, id)
        assert.Error(t, err)
        assert.Equal(t, service.ErrTagNotFound, err)
        mockRepo.AssertExpectations(t)
    })
}

// Test batch tag creation
func TestBatchCreateTags(t *testing.T) {
    mockRepo, tagService, ctx := setupTest(t)

    t.Run("successful batch creation", func(t *testing.T) {
        tags := []*models.Tag{
            {
                CreatorID: "test-user-123",
                Location: models.Location{
                    Latitude:  40.7128,
                    Longitude: -74.0060,
                    Altitude:  10.0,
                    Geohash:   "dr5r9ydj",
                },
                Content: "Tag 1",
            },
            {
                CreatorID: "test-user-123",
                Location: models.Location{
                    Latitude:  40.7129,
                    Longitude: -74.0061,
                    Altitude:  10.0,
                    Geohash:   "dr5r9ydj",
                },
                Content: "Tag 2",
            },
        }

        expectedTags := make([]*models.Tag, len(tags))
        for i, tag := range tags {
            expectedTag := *tag
            expectedTag.ID = primitive.NewObjectID()
            expectedTags[i] = &expectedTag
        }

        mockRepo.On("BatchCreateTags", ctx, tags).Return(expectedTags, nil)

        createdTags, err := tagService.BatchCreateTags(ctx, tags)
        require.NoError(t, err)
        assert.Len(t, createdTags, 2)
        assert.Equal(t, expectedTags, createdTags)
        mockRepo.AssertExpectations(t)
    })

    t.Run("validation error in batch", func(t *testing.T) {
        tags := []*models.Tag{
            {
                CreatorID: "test-user-123",
                Location: models.Location{
                    Latitude:  40.7128,
                    Longitude: -74.0060,
                    Geohash:   "dr5r9ydj",
                },
            },
            {
                CreatorID: "", // Invalid: empty creator ID
                Location: models.Location{
                    Latitude:  200, // Invalid: latitude > 90
                    Longitude: -74.0060,
                },
            },
        }

        _, err := tagService.BatchCreateTags(ctx, tags)
        assert.Error(t, err)
        mockRepo.AssertNotCalled(t, "BatchCreateTags")
    })
}
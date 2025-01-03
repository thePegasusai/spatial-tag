// Package config provides configuration management for the Tag Service with enhanced
// security and validation features.
package config

import (
	"errors"
	"fmt"
	"time"

	"github.com/caarlos0/env/v6" // v6.10.0
)

// Default configuration values
const (
	DefaultMongoTimeout     = 10 * time.Second
	DefaultGRPCPort        = 50051
	DefaultMaxPoolSize     = 100
	DefaultCleanupInterval = 1 * time.Hour
	DefaultTagExpiration   = 24 * time.Hour
	DefaultVisibilityRadius = 50.0
	DefaultMaxTagsPerUser  = 100
)

// Environment types
const (
	EnvDevelopment = "development"
	EnvStaging     = "staging"
	EnvProduction  = "production"
)

// Config represents the main configuration structure for the Tag Service
type Config struct {
	Environment string `env:"ENV" envDefault:"development"`
	Version     string `env:"VERSION" envDefault:"1.0.0"`
	Mongo       MongoConfig
	GRPC        GRPCConfig
	Tag         TagConfig
	Security    SecurityConfig
}

// MongoConfig holds MongoDB-specific configuration
type MongoConfig struct {
	URI        string        `env:"MONGO_URI,required"`
	Database   string        `env:"MONGO_DB,required"`
	Collection string        `env:"MONGO_COLLECTION,required"`
	Timeout    time.Duration `env:"MONGO_TIMEOUT" envDefault:"10s"`
	MaxPoolSize int          `env:"MONGO_MAX_POOL_SIZE" envDefault:"100"`
	EnableSSL  bool          `env:"MONGO_ENABLE_SSL" envDefault:"true"`
	ReplicaSet string        `env:"MONGO_REPLICA_SET"`
}

// GRPCConfig holds gRPC server configuration
type GRPCConfig struct {
	Host      string        `env:"GRPC_HOST" envDefault:"0.0.0.0"`
	Port      int          `env:"GRPC_PORT" envDefault:"50051"`
	Timeout   time.Duration `env:"GRPC_TIMEOUT" envDefault:"30s"`
	EnableTLS bool         `env:"GRPC_ENABLE_TLS" envDefault:"true"`
	CertFile  string        `env:"GRPC_CERT_FILE"`
	KeyFile   string        `env:"GRPC_KEY_FILE"`
}

// TagConfig holds tag-specific service configuration
type TagConfig struct {
	DefaultVisibilityRadius float64       `env:"TAG_DEFAULT_VISIBILITY_RADIUS" envDefault:"50.0"`
	DefaultExpiration      time.Duration `env:"TAG_DEFAULT_EXPIRATION" envDefault:"24h"`
	CleanupInterval       time.Duration `env:"TAG_CLEANUP_INTERVAL" envDefault:"1h"`
	MaxTagsPerUser        int          `env:"TAG_MAX_PER_USER" envDefault:"100"`
	MaxTagSize           int          `env:"TAG_MAX_SIZE" envDefault:"1048576"` // 1MB
	EnableContentValidation bool       `env:"TAG_ENABLE_CONTENT_VALIDATION" envDefault:"true"`
}

// SecurityConfig holds security-specific configuration
type SecurityConfig struct {
	EnableAuditLog    bool          `env:"SECURITY_ENABLE_AUDIT_LOG" envDefault:"true"`
	EncryptionKey     string        `env:"SECURITY_ENCRYPTION_KEY,required"`
	TokenExpiration   time.Duration `env:"SECURITY_TOKEN_EXPIRATION" envDefault:"1h"`
	MaxFailedAttempts int          `env:"SECURITY_MAX_FAILED_ATTEMPTS" envDefault:"5"`
}

// LoadConfig loads and validates configuration from environment variables
func LoadConfig() (*Config, error) {
	cfg := &Config{}
	
	opts := env.Options{
		Prefix: "TAG_SERVICE_",
		OnSet: func(tag string, value interface{}, isDefault bool) {
			// Log configuration loading for audit purposes
		},
	}

	if err := env.Parse(cfg, opts); err != nil {
		return nil, fmt.Errorf("failed to parse config: %w", err)
	}

	if err := cfg.Validate(); err != nil {
		return nil, fmt.Errorf("config validation failed: %w", err)
	}

	return cfg, nil
}

// Validate performs comprehensive configuration validation
func (c *Config) Validate() error {
	// Validate environment
	switch c.Environment {
	case EnvDevelopment, EnvStaging, EnvProduction:
	default:
		return errors.New("invalid environment specified")
	}

	// Validate MongoDB configuration
	if err := c.validateMongoConfig(); err != nil {
		return fmt.Errorf("mongodb config validation failed: %w", err)
	}

	// Validate gRPC configuration
	if err := c.validateGRPCConfig(); err != nil {
		return fmt.Errorf("grpc config validation failed: %w", err)
	}

	// Validate tag configuration
	if err := c.validateTagConfig(); err != nil {
		return fmt.Errorf("tag config validation failed: %w", err)
	}

	// Validate security configuration
	if err := c.validateSecurityConfig(); err != nil {
		return fmt.Errorf("security config validation failed: %w", err)
	}

	return nil
}

func (c *Config) validateMongoConfig() error {
	if c.Mongo.URI == "" {
		return errors.New("mongodb URI is required")
	}
	if c.Mongo.Database == "" {
		return errors.New("mongodb database name is required")
	}
	if c.Mongo.Collection == "" {
		return errors.New("mongodb collection name is required")
	}
	if c.Mongo.Timeout < time.Second {
		return errors.New("mongodb timeout must be at least 1 second")
	}
	if c.Mongo.MaxPoolSize < 1 {
		return errors.New("mongodb max pool size must be positive")
	}
	
	// Production-specific validations
	if c.Environment == EnvProduction {
		if !c.Mongo.EnableSSL {
			return errors.New("SSL must be enabled in production")
		}
		if c.Mongo.ReplicaSet == "" {
			return errors.New("replica set is required in production")
		}
	}
	
	return nil
}

func (c *Config) validateGRPCConfig() error {
	if c.GRPC.Port < 1024 || c.GRPC.Port > 65535 {
		return errors.New("invalid gRPC port number")
	}
	if c.GRPC.Timeout < time.Second {
		return errors.New("gRPC timeout must be at least 1 second")
	}

	// Production-specific validations
	if c.Environment == EnvProduction {
		if !c.GRPC.EnableTLS {
			return errors.New("TLS must be enabled in production")
		}
		if c.GRPC.CertFile == "" || c.GRPC.KeyFile == "" {
			return errors.New("TLS certificates are required in production")
		}
	}

	return nil
}

func (c *Config) validateTagConfig() error {
	if c.Tag.DefaultVisibilityRadius <= 0 {
		return errors.New("visibility radius must be positive")
	}
	if c.Tag.DefaultExpiration < time.Minute {
		return errors.New("tag expiration must be at least 1 minute")
	}
	if c.Tag.CleanupInterval < time.Minute {
		return errors.New("cleanup interval must be at least 1 minute")
	}
	if c.Tag.MaxTagsPerUser < 1 {
		return errors.New("max tags per user must be positive")
	}
	if c.Tag.MaxTagSize < 1 {
		return errors.New("max tag size must be positive")
	}

	return nil
}

func (c *Config) validateSecurityConfig() error {
	if c.Security.EncryptionKey == "" {
		return errors.New("encryption key is required")
	}
	if len(c.Security.EncryptionKey) < 32 {
		return errors.New("encryption key must be at least 32 characters")
	}
	if c.Security.TokenExpiration < time.Minute {
		return errors.New("token expiration must be at least 1 minute")
	}
	if c.Security.MaxFailedAttempts < 1 {
		return errors.New("max failed attempts must be positive")
	}

	// Production-specific validations
	if c.Environment == EnvProduction {
		if !c.Security.EnableAuditLog {
			return errors.New("audit logging must be enabled in production")
		}
	}

	return nil
}
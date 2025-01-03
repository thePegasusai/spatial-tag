package server

import (
    "context"
    "fmt"
    "net"
    "time"

    grpc_middleware "github.com/grpc-ecosystem/go-grpc-middleware" // v2.0.0
    grpc_prometheus "github.com/grpc-ecosystem/go-grpc-prometheus"  // v1.2.0
    "github.com/prometheus/client_golang/prometheus" // v1.11.0
    "google.golang.org/grpc" // v1.45.0
    "google.golang.org/grpc/codes" // v1.1.0
    "google.golang.org/grpc/credentials" // v1.45.0
    "google.golang.org/grpc/health/grpc_health_v1" // v1.45.0
    "google.golang.org/grpc/keepalive" // v1.45.0
    "google.golang.org/grpc/status" // v1.1.0

    "internal/config"
    "internal/service"
    pb "pkg/proto"
)

var (
    // Server metrics
    grpcRequestDuration = prometheus.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "tag_service_grpc_request_duration_seconds",
            Help:    "Duration of gRPC requests in seconds",
            Buckets: prometheus.ExponentialBuckets(0.01, 2, 10),
        },
        []string{"method", "status"},
    )

    grpcRequestTotal = prometheus.NewCounterVec(
        prometheus.CounterOpts{
            Name: "tag_service_grpc_requests_total",
            Help: "Total number of gRPC requests",
        },
        []string{"method", "status"},
    )
)

// Server represents the gRPC server for tag service
type Server struct {
    pb.UnimplementedTagServiceServer
    tagService *service.TagService
    config     *config.Config
    server     *grpc.Server
}

// NewServer creates a new gRPC server instance with all middleware and configuration
func NewServer(tagService *service.TagService, cfg *config.Config) (*Server, error) {
    if tagService == nil {
        return nil, fmt.Errorf("tag service is required")
    }

    // Register metrics
    prometheus.MustRegister(grpcRequestDuration, grpcRequestTotal)

    // Configure server options
    opts := []grpc.ServerOption{
        grpc.KeepaliveParams(keepalive.ServerParameters{
            MaxConnectionIdle: 5 * time.Minute,
            MaxConnectionAge:  30 * time.Minute,
            Time:             1 * time.Minute,
            Timeout:          20 * time.Second,
        }),
        grpc.KeepaliveEnforcementPolicy(keepalive.EnforcementPolicy{
            MinTime:             1 * time.Minute,
            PermitWithoutStream: true,
        }),
        grpc.MaxConcurrentStreams(1000),
        grpc.ChainUnaryInterceptor(
            grpc_prometheus.UnaryServerInterceptor,
            unaryServerInterceptor(),
        ),
        grpc.ChainStreamInterceptor(
            grpc_prometheus.StreamServerInterceptor,
            streamServerInterceptor(),
        ),
    }

    // Configure TLS if enabled
    if cfg.GRPC.EnableTLS {
        creds, err := credentials.NewServerTLSFromFile(
            cfg.GRPC.CertFile,
            cfg.GRPC.KeyFile,
        )
        if err != nil {
            return nil, fmt.Errorf("failed to load TLS credentials: %v", err)
        }
        opts = append(opts, grpc.Creds(creds))
    }

    // Create gRPC server
    grpcServer := grpc.NewServer(opts...)

    // Create server instance
    server := &Server{
        tagService: tagService,
        config:     cfg,
        server:     grpcServer,
    }

    // Register services
    pb.RegisterTagServiceServer(grpcServer, server)
    grpc_health_v1.RegisterHealthServer(grpcServer, server)
    grpc_prometheus.Register(grpcServer)

    return server, nil
}

// Start starts the gRPC server
func (s *Server) Start(ctx context.Context) error {
    addr := fmt.Sprintf("%s:%d", s.config.GRPC.Host, s.config.GRPC.Port)
    lis, err := net.Listen("tcp", addr)
    if err != nil {
        return fmt.Errorf("failed to listen: %v", err)
    }

    go func() {
        <-ctx.Done()
        s.server.GracefulStop()
    }()

    return s.server.Serve(lis)
}

// CreateTag implements the CreateTag RPC method
func (s *Server) CreateTag(ctx context.Context, req *pb.CreateTagRequest) (*pb.Tag, error) {
    timer := prometheus.NewTimer(grpcRequestDuration.WithLabelValues("CreateTag", ""))
    defer timer.ObserveDuration()

    if err := validateCreateTagRequest(req); err != nil {
        grpcRequestTotal.WithLabelValues("CreateTag", "invalid").Inc()
        return nil, status.Error(codes.InvalidArgument, err.Error())
    }

    tag, err := s.tagService.CreateTag(ctx, convertToModelTag(req))
    if err != nil {
        grpcRequestTotal.WithLabelValues("CreateTag", "error").Inc()
        return nil, status.Error(codes.Internal, "failed to create tag")
    }

    grpcRequestTotal.WithLabelValues("CreateTag", "success").Inc()
    return convertToProtoTag(tag), nil
}

// GetNearbyTags implements the GetNearbyTags RPC method
func (s *Server) GetNearbyTags(ctx context.Context, req *pb.GetNearbyTagsRequest) (*pb.GetNearbyTagsResponse, error) {
    timer := prometheus.NewTimer(grpcRequestDuration.WithLabelValues("GetNearbyTags", ""))
    defer timer.ObserveDuration()

    if err := validateGetNearbyTagsRequest(req); err != nil {
        grpcRequestTotal.WithLabelValues("GetNearbyTags", "invalid").Inc()
        return nil, status.Error(codes.InvalidArgument, err.Error())
    }

    tags, err := s.tagService.GetNearbyTags(ctx, convertToModelLocation(req.Location), req.RadiusMeters, req.UserId)
    if err != nil {
        grpcRequestTotal.WithLabelValues("GetNearbyTags", "error").Inc()
        return nil, status.Error(codes.Internal, "failed to get nearby tags")
    }

    grpcRequestTotal.WithLabelValues("GetNearbyTags", "success").Inc()
    return &pb.GetNearbyTagsResponse{
        Tags: convertToProtoTags(tags),
        SearchRadiusMeters: req.RadiusMeters,
        Timestamp: timestamppb.Now(),
    }, nil
}

// StreamTagUpdates implements the StreamTagUpdates RPC method
func (s *Server) StreamTagUpdates(req *pb.StreamTagUpdatesRequest, stream pb.TagService_StreamTagUpdatesServer) error {
    timer := prometheus.NewTimer(grpcRequestDuration.WithLabelValues("StreamTagUpdates", ""))
    defer timer.ObserveDuration()

    if err := validateStreamTagUpdatesRequest(req); err != nil {
        grpcRequestTotal.WithLabelValues("StreamTagUpdates", "invalid").Inc()
        return status.Error(codes.InvalidArgument, err.Error())
    }

    updates := s.tagService.SubscribeToUpdates(stream.Context(), req.Location, req.RadiusMeters)
    for {
        select {
        case <-stream.Context().Done():
            grpcRequestTotal.WithLabelValues("StreamTagUpdates", "cancelled").Inc()
            return status.Error(codes.Canceled, "stream cancelled by client")
        case update := <-updates:
            if err := stream.Send(convertToProtoTag(update)); err != nil {
                grpcRequestTotal.WithLabelValues("StreamTagUpdates", "error").Inc()
                return status.Error(codes.Internal, "failed to send update")
            }
            grpcRequestTotal.WithLabelValues("StreamTagUpdates", "success").Inc()
        }
    }
}

// Check implements the health checking service
func (s *Server) Check(ctx context.Context, req *grpc_health_v1.HealthCheckRequest) (*grpc_health_v1.HealthCheckResponse, error) {
    return &grpc_health_v1.HealthCheckResponse{
        Status: grpc_health_v1.HealthCheckResponse_SERVING,
    }, nil
}

// Watch implements the health checking service streaming method
func (s *Server) Watch(req *grpc_health_v1.HealthCheckRequest, stream grpc_health_v1.Health_WatchServer) error {
    return status.Error(codes.Unimplemented, "health check watching not implemented")
}

// Helper functions for request validation and conversion are implemented here...
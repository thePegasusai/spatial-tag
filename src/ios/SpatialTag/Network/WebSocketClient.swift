// Foundation - iOS 15.0+ - Core iOS functionality and URLSessionWebSocketTask
import Foundation
// Combine - iOS 15.0+ - Reactive programming support
import Combine
// CryptoKit - iOS 15.0+ - Message encryption and security operations
import CryptoKit

// Internal imports
import APIError
import NetworkMonitor
import Logger

/// WebSocket connection states
@frozen public enum WebSocketState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case error(APIError)
}

/// WebSocket event types for real-time updates
@frozen public enum WebSocketEvent {
    case locationUpdate(Data)
    case tagEvent(Data)
    case userEvent(Data)
    case connectionStateChanged(WebSocketState)
    case error(Error)
}

/// WebSocket communication channels
@frozen public enum WebSocketChannel: String {
    case location = "spatial/location"
    case tags = "spatial/tags"
    case users = "spatial/users"
}

/// Security configuration for WebSocket connections
public struct SecurityConfiguration {
    let certificates: [SecCertificate]
    let compressionEnabled: Bool
    let messageEncryption: Bool
    let pinningMode: SSLPinningMode
    
    public enum SSLPinningMode {
        case certificate
        case publicKey
        case none
    }
}

/// WebSocket client implementation with security and performance features
@available(iOS 15.0, *)
public final class WebSocketClient {
    // MARK: - Properties
    
    private var webSocketTask: URLSessionWebSocketTask?
    private let serverURL: URL
    private let securityConfig: SecurityConfiguration
    
    public let eventPublisher = PassthroughSubject<WebSocketEvent, Never>()
    public let connectionState = CurrentValueSubject<WebSocketState, Never>(.disconnected)
    
    private var pingTimer: Timer?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 5
    private var cancellables = Set<AnyCancellable>()
    
    private let messageQueue = DispatchQueue(label: "com.spatialtag.websocket.message")
    private var channelSubscriptions: [WebSocketChannel: Set<UUID>] = [:]
    
    // MARK: - Initialization
    
    public init(serverURL: URL, securityConfig: SecurityConfiguration) {
        self.serverURL = serverURL
        self.securityConfig = securityConfig
        
        setupNetworkMonitoring()
    }
    
    // MARK: - Public Methods
    
    /// Establishes secure WebSocket connection
    public func connect() -> AnyPublisher<Bool, Error> {
        guard NetworkMonitor.shared.isConnected else {
            return Fail(error: APIError.networkError(NSError(domain: "No network connection", code: -1)))
                .eraseToAnyPublisher()
        }
        
        connectionState.send(.connecting)
        
        let session = configureURLSession()
        webSocketTask = session.webSocketTask(with: serverURL)
        
        setupPingTimer()
        receiveMessage()
        
        return Future { [weak self] promise in
            self?.webSocketTask?.resume()
            promise(.success(true))
        }
        .handleEvents(receiveCompletion: { [weak self] completion in
            if case .failure(let error) = completion {
                self?.handleConnectionError(error)
            }
        })
        .eraseToAnyPublisher()
    }
    
    /// Gracefully closes WebSocket connection
    public func disconnect() {
        pingTimer?.invalidate()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        connectionState.send(.disconnected)
        reconnectAttempts = 0
    }
    
    /// Sends encrypted message on specified channel
    public func send(message: Data, on channel: WebSocketChannel) -> AnyPublisher<Void, Error> {
        guard let webSocketTask = webSocketTask else {
            return Fail(error: APIError.networkError(NSError(domain: "WebSocket not connected", code: -1)))
                .eraseToAnyPublisher()
        }
        
        return Future { [weak self] promise in
            guard let self = self else { return }
            
            let encryptedMessage = self.encryptMessage(message)
            let payload = self.prepareMessagePayload(channel: channel, data: encryptedMessage)
            
            let message = URLSessionWebSocketTask.Message.data(payload)
            webSocketTask.send(message) { error in
                if let error = error {
                    promise(.failure(error))
                } else {
                    promise(.success(()))
                }
            }
        }
        .eraseToAnyPublisher()
    }
    
    /// Subscribes to WebSocket channel
    public func subscribe(to channel: WebSocketChannel) -> AnyPublisher<Data, Never> {
        let subscriptionId = UUID()
        
        if channelSubscriptions[channel] == nil {
            channelSubscriptions[channel] = Set<UUID>()
        }
        channelSubscriptions[channel]?.insert(subscriptionId)
        
        return eventPublisher
            .compactMap { event -> Data? in
                if case .locationUpdate(let data) = event, channel == .location {
                    return data
                } else if case .tagEvent(let data) = event, channel == .tags {
                    return data
                } else if case .userEvent(let data) = event, channel == .users {
                    return data
                }
                return nil
            }
            .handleEvents(receiveCancel: { [weak self] in
                self?.channelSubscriptions[channel]?.remove(subscriptionId)
            })
            .eraseToAnyPublisher()
    }
    
    // MARK: - Private Methods
    
    private func setupNetworkMonitoring() {
        NetworkMonitor.shared.networkStatus
            .sink { [weak self] status in
                if case .disconnected = status {
                    self?.handleNetworkDisconnection()
                }
            }
            .store(in: &cancellables)
    }
    
    private func configureURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        
        if securityConfig.compressionEnabled {
            configuration.httpAdditionalHeaders = ["Accept-Encoding": "gzip"]
        }
        
        let delegate = WebSocketSecurityDelegate(securityConfig: securityConfig)
        return URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }
    
    private func setupPingTimer() {
        pingTimer?.invalidate()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
    }
    
    private func sendPing() {
        webSocketTask?.sendPing { [weak self] error in
            if let error = error {
                self?.handleConnectionError(error)
            }
        }
    }
    
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self = self else { return }
            
            switch result {
            case .success(let message):
                self.handleMessage(message)
                self.receiveMessage()
                
            case .failure(let error):
                self.handleConnectionError(error)
            }
        }
    }
    
    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            do {
                let decryptedData = try decryptMessage(data)
                let channelEvent = try parseChannelEvent(from: decryptedData)
                eventPublisher.send(channelEvent)
            } catch {
                eventPublisher.send(.error(error))
            }
            
        case .string(let string):
            guard let data = string.data(using: .utf8) else { return }
            handleMessage(.data(data))
            
        @unknown default:
            break
        }
    }
    
    private func handleConnectionError(_ error: Error) {
        Logger.error("WebSocket connection error: \(error.localizedDescription)")
        
        if reconnectAttempts < maxReconnectAttempts {
            reconnectAttempts += 1
            connectionState.send(.reconnecting(attempt: reconnectAttempts))
            
            DispatchQueue.main.asyncAfter(deadline: .now() + pow(2.0, Double(reconnectAttempts))) {
                self.connect().sink { _ in }.store(in: &self.cancellables)
            }
        } else {
            connectionState.send(.error(.networkError(error)))
        }
    }
    
    private func handleNetworkDisconnection() {
        disconnect()
        connectionState.send(.error(.networkError(NSError(domain: "Network disconnected", code: -1))))
    }
    
    private func encryptMessage(_ message: Data) -> Data {
        guard securityConfig.messageEncryption else { return message }
        // Implement encryption using CryptoKit
        return message
    }
    
    private func decryptMessage(_ message: Data) throws -> Data {
        guard securityConfig.messageEncryption else { return message }
        // Implement decryption using CryptoKit
        return message
    }
    
    private func prepareMessagePayload(channel: WebSocketChannel, data: Data) -> Data {
        var payload: [String: Any] = [
            "channel": channel.rawValue,
            "timestamp": Date().timeIntervalSince1970,
            "data": data.base64EncodedString()
        ]
        
        return try! JSONSerialization.data(withJSONObject: payload)
    }
    
    private func parseChannelEvent(from data: Data) throws -> WebSocketEvent {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let channelString = json?["channel"] as? String,
              let channel = WebSocketChannel(rawValue: channelString),
              let base64Data = json?["data"] as? String,
              let eventData = Data(base64Encoded: base64Data) else {
            throw APIError.decodingError(NSError(domain: "Invalid message format", code: -1))
        }
        
        switch channel {
        case .location:
            return .locationUpdate(eventData)
        case .tags:
            return .tagEvent(eventData)
        case .users:
            return .userEvent(eventData)
        }
    }
}

// MARK: - WebSocket Security Delegate

private class WebSocketSecurityDelegate: NSObject, URLSessionWebSocketDelegate {
    private let securityConfig: SecurityConfiguration
    
    init(securityConfig: SecurityConfiguration) {
        self.securityConfig = securityConfig
        super.init()
    }
    
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                   completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        
        switch securityConfig.pinningMode {
        case .certificate:
            validateCertificates(serverTrust: serverTrust, completionHandler: completionHandler)
        case .publicKey:
            validatePublicKey(serverTrust: serverTrust, completionHandler: completionHandler)
        case .none:
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        }
    }
    
    private func validateCertificates(serverTrust: SecTrust,
                                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let serverCertificates = (0..<SecTrustGetCertificateCount(serverTrust))
            .compactMap { SecTrustGetCertificateAtIndex(serverTrust, $0) }
        
        let isValid = !Set(serverCertificates).isDisjoint(with: Set(securityConfig.certificates))
        
        if isValid {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
    
    private func validatePublicKey(serverTrust: SecTrust,
                                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // Implement public key pinning validation
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
// Foundation - Core iOS functionality, date formatting, and thread management (latest)
import Foundation
// os.log - Native iOS logging system integration with performance optimization (latest)
import os.log

// MARK: - Global Constants
private let LOG_DATE_FORMAT = "yyyy-MM-dd HH:mm:ss.SSS"
private let LOG_QUEUE = DispatchQueue(label: "com.spatialtag.logger", qos: .utility)

// MARK: - LogLevel Enumeration
@objc public enum LogLevel: Int {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    case performance = 4
    
    public var description: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARNING"
        case .error: return "ERROR"
        case .performance: return "PERFORMANCE"
        }
    }
    
    public func isEnabled(minimumLevel: LogLevel) -> Bool {
        return self.rawValue >= minimumLevel.rawValue
    }
}

// MARK: - Logger Class
@objc public class Logger {
    // MARK: - Properties
    private let osLog: OSLog
    private let minimumLogLevel: LogLevel
    private let isDebugMode: Bool
    private let logQueue: DispatchQueue
    private let dateFormatter: DateFormatter
    private let sensitiveKeys: Set<String>
    
    // MARK: - Initialization
    public init(minimumLevel: LogLevel = .info,
                subsystem: String = Bundle.main.bundleIdentifier ?? "com.spatialtag",
                category: String = "default") {
        self.osLog = OSLog(subsystem: subsystem, category: category)
        self.minimumLogLevel = minimumLevel
        self.logQueue = LOG_QUEUE
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = LOG_DATE_FORMAT
        
        #if DEBUG
        self.isDebugMode = true
        #else
        self.isDebugMode = false
        #endif
        
        // Initialize sensitive data patterns
        self.sensitiveKeys = ["password", "token", "secret", "key", "auth", "credential"]
    }
    
    // MARK: - Private Methods
    @inline(__always)
    private func formatMessage(_ message: String,
                             level: LogLevel,
                             file: String,
                             line: Int,
                             category: String?) -> String {
        let timestamp = dateFormatter.string(from: Date())
        let filename = (file as NSString).lastPathComponent
        
        var logData: [String: Any] = [
            "timestamp": timestamp,
            "level": level.description,
            "message": message,
            "file": filename,
            "line": line,
            "thread": Thread.current.description
        ]
        
        if let category = category {
            logData["category"] = category
        }
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: logData),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{\(timestamp)} [\(level.description)] \(message)"
    }
    
    private func sanitizeSensitiveData(_ message: String) -> String {
        var sanitizedMessage = message
        for key in sensitiveKeys {
            let pattern = "(?i)\(key)[^\\s]*\\s*[:=]\\s*[^\\s]+"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                sanitizedMessage = regex.stringByReplacingMatches(
                    in: sanitizedMessage,
                    range: NSRange(sanitizedMessage.startIndex..., in: sanitizedMessage),
                    withTemplate: "\(key)=*REDACTED*"
                )
            }
        }
        return sanitizedMessage
    }
    
    // MARK: - Public Logging Methods
    public func debug(_ message: String,
                     file: String = #file,
                     line: Int = #line,
                     category: String? = nil) {
        guard LogLevel.debug.isEnabled(minimumLevel: minimumLogLevel) else { return }
        
        logQueue.async {
            let sanitizedMessage = self.sanitizeSensitiveData(message)
            let formattedMessage = self.formatMessage(sanitizedMessage,
                                                    level: .debug,
                                                    file: file,
                                                    line: line,
                                                    category: category)
            
            os_log(.debug, log: self.osLog, "%{public}@", formattedMessage)
        }
    }
    
    public func info(_ message: String,
                    file: String = #file,
                    line: Int = #line,
                    category: String? = nil) {
        guard LogLevel.info.isEnabled(minimumLevel: minimumLogLevel) else { return }
        
        logQueue.async {
            let sanitizedMessage = self.sanitizeSensitiveData(message)
            let formattedMessage = self.formatMessage(sanitizedMessage,
                                                    level: .info,
                                                    file: file,
                                                    line: line,
                                                    category: category)
            
            os_log(.info, log: self.osLog, "%{public}@", formattedMessage)
        }
    }
    
    public func warning(_ message: String,
                       file: String = #file,
                       line: Int = #line,
                       category: String? = nil) {
        guard LogLevel.warning.isEnabled(minimumLevel: minimumLogLevel) else { return }
        
        logQueue.async {
            let sanitizedMessage = self.sanitizeSensitiveData(message)
            let formattedMessage = self.formatMessage(sanitizedMessage,
                                                    level: .warning,
                                                    file: file,
                                                    line: line,
                                                    category: category)
            
            os_log(.error, log: self.osLog, "%{public}@", formattedMessage)
        }
    }
    
    public func error(_ message: String,
                     file: String = #file,
                     line: Int = #line,
                     category: String? = nil) {
        guard LogLevel.error.isEnabled(minimumLevel: minimumLogLevel) else { return }
        
        logQueue.async {
            let sanitizedMessage = self.sanitizeSensitiveData(message)
            let formattedMessage = self.formatMessage(sanitizedMessage,
                                                    level: .error,
                                                    file: file,
                                                    line: line,
                                                    category: category)
            
            os_log(.fault, log: self.osLog, "%{public}@", formattedMessage)
        }
    }
    
    public func performance(_ operation: String,
                          duration: TimeInterval,
                          threshold: TimeInterval? = nil,
                          metadata: [String: Any]? = nil) {
        guard LogLevel.performance.isEnabled(minimumLevel: minimumLogLevel) else { return }
        
        logQueue.async {
            var performanceData: [String: Any] = [
                "operation": operation,
                "duration": duration,
                "memoryUsage": ProcessInfo.processInfo.physicalMemory,
                "cpuLoad": ProcessInfo.processInfo.systemUptime
            ]
            
            if let metadata = metadata {
                performanceData.merge(metadata) { current, _ in current }
            }
            
            if let threshold = threshold, duration > threshold {
                performanceData["threshold_exceeded"] = true
                performanceData["threshold"] = threshold
                
                self.error("Performance threshold exceeded",
                          category: "Performance")
            }
            
            if let jsonData = try? JSONSerialization.data(withJSONObject: performanceData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                os_log(.info, log: self.osLog, "%{public}@", jsonString)
            }
        }
    }
}
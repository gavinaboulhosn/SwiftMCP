import Foundation
import os.log

private let logger = Logger(subsystem: "SwiftMCP", category: "StdioTransport")

// MARK: - StdioTransportOptions

extension StdioTransportConfiguration {
  public static let dummyData = StdioTransportConfiguration(
    command: "/dev/null",
    arguments: ["some", "args"],
    environment: ["another": "env"],
    baseConfiguration: .dummyData)
}

public struct StdioTransportConfiguration: Codable {
  public var command: String
  public var arguments: [String]
  public var environment: [String: String]
  public var baseConfiguration: TransportConfiguration
  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    baseConfiguration: TransportConfiguration = .default)
  {
    self.command = command
    self.arguments = arguments
    self.environment = environment
    self.baseConfiguration = baseConfiguration
  }
}

// MARK: - Platform-specific implementation
#if os(macOS) || os(Linux)
/// Transport implementation using stdio for process-based communication.
/// This transport is designed for long-running MCP servers launched via command line.
/// Transport implementation using stdio for process-based communication.
/// This transport is designed for long-running MCP servers launched via command line.
public actor StdioTransport: MCPTransport, RetryableTransport {

  // MARK: Lifecycle

  /// Initialize a stdio transport for a command-line MCP server
  /// - Parameters:
  ///   - configuration: Transport configuration
  public init(configuration: StdioTransportConfiguration) {
    _configuration = configuration
  }

  /// Convenience initializer
  public convenience init(
    command: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    configuration: TransportConfiguration = .default)
  {
    let configuration = StdioTransportConfiguration(
      command: command,
      arguments: arguments,
      environment: environment,
      baseConfiguration: configuration)
    self.init(configuration: configuration)
  }

  // MARK: Public

  public var configuration: TransportConfiguration {
    _configuration.baseConfiguration
  }

  public var isRunning: Bool {
    process?.isRunning ?? false
  }

  public var messages: AsyncThrowingStream<JSONRPCMessage, Error> {
    get throws {
      let (stream, continuation) = AsyncThrowingStream.makeStream(of: JSONRPCMessage.self)
      messagesContinuation = continuation
      return stream
    }
  }

  public var stateMessages: AsyncStream<TransportState> {
    get throws {
      let (stream, continuation) = AsyncStream.makeStream(of: TransportState.self)
      transportStateContinuation = continuation
      return stream
    }
  }

  public private(set) var state = TransportState.disconnected {
    didSet {
      let newState = state
      logger.info("client state update: \(oldValue) -> \(newState)")
      transportStateContinuation?.yield(with: .success(newState))
    }
  }

  public func start() async throws {
    guard state != .connected else {
      logger.warning("Transport already connected")
      return
    }

    let inPipe = Pipe()
    let outPipe = Pipe()
    let errPipe = Pipe()

    let newProcess = Process()
    newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env") // locate command in PATH
    newProcess.arguments = [command] + arguments

    // Merge environment
    var processEnv = ProcessInfo.processInfo.environment
    environment.forEach { processEnv[$0] = $1 }

    // Ensure PATH includes typical node/npm locations
    if var path = processEnv["PATH"] {
      let additionalPaths = [
        "/usr/local/bin",
        "/usr/local/npm/bin",
        "\(processEnv["HOME"] ?? "")/node_modules/.bin",
        "\(processEnv["HOME"] ?? "")/.npm-global/bin",
        "/opt/homebrew/bin",
        "/usr/local/opt/node/bin",
      ]
      path = (additionalPaths + [path]).joined(separator: ":")
      processEnv["PATH"] = path
    }
    newProcess.environment = processEnv

    // Assign pipes
    newProcess.standardInput = inPipe
    newProcess.standardOutput = outPipe
    newProcess.standardError = errPipe

    newProcess.terminationHandler = { [weak self] proc in
      logger.debug("Process terminated with exit code \(proc.terminationStatus)")
      Task {
        await self?.stop()
      }
    }

    // Keep references so we can use them later
    process = newProcess
    inputPipe = inPipe
    outputPipe = outPipe
    errorPipe = errPipe

    // Monitor stdout and stderr
    // We'll store these tasks in processTask, so they can be canceled on stop()
    processTask = Task {
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await self.monitorStdErr(errPipe) }
        group.addTask { await self.readMessages(outPipe) }
      }
    }

    try newProcess.run()
    state = .connected
  }

  public func stop() {
    guard state != .disconnected else {
      return
    }

    state = .disconnected

    processTask?.cancel()
    processTask = nil

    if let proc = process, proc.isRunning {
      proc.terminate()
      Task.detached {
        proc.waitUntilExit()
      }
    }

    inputPipe?.fileHandleForWriting.closeFile()
    outputPipe?.fileHandleForReading.closeFile()
    errorPipe?.fileHandleForReading.closeFile()

    process = nil
    inputPipe = nil
    outputPipe = nil
    errorPipe = nil

    // Finish the message stream
    messagesContinuation?.finish()
    messagesContinuation = nil
    transportStateContinuation?.finish()
    transportStateContinuation = nil
  }

  public func send(_ message: JSONRPCMessage, timeout _: TimeInterval? = nil) async throws {
    guard state == .connected else {
      throw TransportError.invalidState("Transport not connected")
    }
    guard let inPipe = inputPipe else {
      throw TransportError.invalidState("Pipe not available")
    }
    var messageData = try validate(message)
    messageData.append(0x0A)
    inPipe.fileHandleForWriting.write(messageData)
  }

  // MARK: Private

  private var _configuration: StdioTransportConfiguration

  // Process & pipes are recreated on each start()
  private var process: Process?
  private var inputPipe: Pipe?
  private var outputPipe: Pipe?
  private var errorPipe: Pipe?

  private var transportStateContinuation: AsyncStream<TransportState>.Continuation?
  private var messagesContinuation: AsyncThrowingStream<JSONRPCMessage, Error>.Continuation?
  private var processTask: Task<Void, Never>?

  // Stored options for constructing the process each time
  private var command: String { _configuration.command }
  private var arguments: [String] { _configuration.arguments }
  private var environment: [String: String] { _configuration.environment }

  // MARK: - Internal reading tasks

  private func monitorStdErr(_ errPipe: Pipe) async {
    do {
      for try await line in errPipe.bytes.lines {
        // Some MCP servers use stderr for logging
        logger.info("[SERVER STDERR] \(line)")
      }
    } catch {
      logger.error("Error reading stderr: \(error)")
    }
  }

  private func readMessages(_ outPipe: Pipe) async {
    do {
      for try await line in outPipe.bytes.lines {
        try Task.checkCancellation()
        guard let data = line.data(using: .utf8) else {
          logger.error("Unable to parse line as UTF-8: \(line)")
          continue
        }
        if let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data) {
          guard let continuation = messagesContinuation else {
            logger.error("Received message with no active listener: \(data)")
            continue
          }
          continuation.yield(message)
        }
      }
      logger.debug("Stdout stream ended gracefully.")
      await stop()
    } catch is CancellationError {
      logger.debug("Stdout read task cancelled.")
    } catch {
      logger.error("Fatal error in reading stdout messages: \(error.localizedDescription)")
      state = .disconnected
      await stop()
    }
  }
}

// MARK: - Async Pipe helpers

extension Pipe {
  struct AsyncBytes: AsyncSequence {
    typealias Element = UInt8

    var pipe: Pipe?

    func makeAsyncIterator() -> AsyncStream<Element>.Iterator {
      AsyncStream { continuation in
        pipe?.fileHandleForReading.readabilityHandler = { @Sendable handle in
          let data = handle.availableData
          guard !data.isEmpty else {
            continuation.finish()
            return
          }
          for byte in data {
            continuation.yield(byte)
          }
        }

        continuation.onTermination = { [weak pipe] _ in
          pipe?.fileHandleForReading.readabilityHandler = nil
        }
      }.makeAsyncIterator()
    }
  }

  var bytes: AsyncBytes {
    AsyncBytes(pipe: self)
  }
}

#else

/// Stub implementation for platforms that don't support Process
public actor StdioTransport: MCPTransport {

  // MARK: Lifecycle

  public init(configuration: StdioTransportConfiguration = .dummyData) {
    _configuration = configuration
  }

  public convenience init(
    command: String,
    arguments: [String] = [],
    environment: [String: String] = [:],
    configuration: TransportConfiguration = .default)
  {
    let configuration = StdioTransportConfiguration(
      command: command,
      arguments: arguments,
      environment: environment,
      baseConfiguration: configuration)
    self.init(configuration: configuration)
  }

  // MARK: Public

  public private(set) var state = TransportState.disconnected

  public var configuration: TransportConfiguration {
    _configuration.baseConfiguration
  }

  public var isRunning: Bool { false }

  public var messages: AsyncThrowingStream<JSONRPCMessage, Error> {
    get throws {
      AsyncThrowingStream { continuation in
        continuation.finish(throwing: TransportError.unsupportedPlatform)
      }
    }
  }

  public var stateMessages: AsyncStream<TransportState> {
    get throws {
      AsyncStream { continuation in
        continuation.finish()
      }
    }
  }

  public func start() async throws {
    throw TransportError.unsupportedPlatform
  }

  public func stop() {
    // No-op
  }

  public func send(_: Data, timeout _: TimeInterval? = nil) async throws {
    throw TransportError.unsupportedPlatform
  }

  // MARK: Private

  private var _configuration: StdioTransportConfiguration

}

#endif

extension TransportError {
  static let unsupportedPlatform = TransportError.notSupported(
    "StdioTransport is not supported on this platform. It requires macOS or Linux.")
}

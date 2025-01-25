import Foundation
import os.log

private let logger = Logger(subsystem: "SwiftMCP", category: "StdioTransport")

public struct StdioTransportOptions {
  public let command: String
  public let arguments: [String]
  public let environment: [String: String]?

  public init(
    command: String,
    arguments: [String] = [],
    environment: [String: String]? = nil
  ) {
    self.command = command
    self.arguments = arguments
    self.environment = environment
  }
}

// MARK: - Platform-specific implementation
#if os(macOS) || os(Linux)
  /// Transport implementation using stdio for process-based communication.
  /// This transport is designed for long-running MCP servers launched via command line.
  /// Transport implementation using stdio for process-based communication.
  /// This transport is designed for long-running MCP servers launched via command line.
  public actor StdioTransport: MCPTransport {
    public private(set) var state: TransportState = .disconnected
    public let configuration: TransportConfiguration

    // Stored options for constructing the process each time
    private let command: String
    private let arguments: [String]
    private let environment: [String: String]?

    // Process & pipes are recreated on each start()
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    private var messagesContinuation: AsyncThrowingStream<Data, Error>.Continuation?
    private var processTask: Task<Void, Never>?

    public var isRunning: Bool {
      process?.isRunning ?? false
    }

    /// Initialize a stdio transport for a command-line MCP server
    /// - Parameters:
    ///   - options: Transport options
    ///   - configuration: Transport configuration
    public init(
      options: StdioTransportOptions,
      configuration: TransportConfiguration = .default
    ) {
      self.command = options.command
      self.arguments = options.arguments
      self.environment = options.environment
      self.configuration = configuration
    }

    /// Convenience initializer
    public init(
      command: String,
      arguments: [String] = [],
      environment: [String: String]? = nil,
      configuration: TransportConfiguration = .default
    ) {
      self.command = command
      self.arguments = arguments
      self.environment = environment
      self.configuration = configuration
    }

    public func messages() -> AsyncThrowingStream<Data, Error> {
      AsyncThrowingStream { continuation in
        self.messagesContinuation = continuation

        // Auto-start if needed
        if self.state == .disconnected {
          Task {
            do {
              try await self.start()
            } catch {
              continuation.finish(throwing: error)
              return
            }
          }
        }

        // When the caller stops consuming the stream, we'll stop the transport.
        continuation.onTermination = { @Sendable [weak self] _ in
          Task {
            await self?.stop()
          }
        }
      }
    }

    public func start() async throws {
      guard state == .disconnected else {
        logger.warning("Transport already connected or connecting")
        return
      }

      self.state = .connecting

      let inPipe = Pipe()
      let outPipe = Pipe()
      let errPipe = Pipe()

      let newProcess = Process()
      newProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")  // locate command in PATH
      newProcess.arguments = [command] + arguments

      // Merge environment
      var processEnv = ProcessInfo.processInfo.environment
      environment?.forEach { processEnv[$0] = $1 }

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
      self.process = newProcess
      self.inputPipe = inPipe
      self.outputPipe = outPipe
      self.errorPipe = errPipe

      // Monitor stdout and stderr
      // We'll store these tasks in processTask, so they can be canceled on stop()
      processTask = Task {
        await withTaskGroup(of: Void.self) { group in
          group.addTask { await self.monitorStdErr(errPipe) }
          group.addTask { await self.readMessages(outPipe) }
        }
      }

      try newProcess.run()
      self.state = .connected
    }

    public func stop() {
      guard state != .disconnected else {
        return
      }

      self.state = .disconnected

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
    }

    public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
      guard state == .connected else {
        throw TransportError.invalidState("Transport not connected")
      }
      guard let inPipe = inputPipe else {
        throw TransportError.invalidState("Pipe not available")
      }

      // Check message size
      guard data.count <= configuration.maxMessageSize else {
        throw TransportError.messageTooLarge(data.count)
      }

      var messageData = data
      messageData.append(0x0A)
      inPipe.fileHandleForWriting.write(messageData)
    }

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
            continue
          }
          messagesContinuation?.yield(data)
        }
      } catch {
        logger.error("Error reading stdout messages: \(error)")
      }
      self.stop()
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
    public private(set) var state: TransportState = .disconnected
    public let configuration: TransportConfiguration

    public var isRunning: Bool { false }

    public init(
      options: StdioTransportOptions,
      configuration: TransportConfiguration = .default
    ) {
      self.configuration = configuration
    }

    public init(
      command: String,
      arguments: [String] = [],
      environment: [String: String]? = nil,
      configuration: TransportConfiguration = .default
    ) {
      self.configuration = configuration
    }

    public func messages() -> AsyncThrowingStream<Data, Error> {
      AsyncThrowingStream { continuation in
        continuation.finish(throwing: TransportError.unsupportedPlatform)
      }
    }

    public func start() async throws {
      throw TransportError.unsupportedPlatform
    }

    public func stop() {
      // No-op
    }

    public func send(_ data: Data, timeout: TimeInterval? = nil) async throws {
      throw TransportError.unsupportedPlatform
    }
  }

#endif

extension TransportError {
  static let unsupportedPlatform = TransportError.notSupported(
    "StdioTransport is not supported on this platform. It requires macOS or Linux."
  )
}

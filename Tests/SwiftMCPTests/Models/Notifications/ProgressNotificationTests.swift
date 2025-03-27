import Testing
import Foundation
@testable import SwiftMCP

@Suite("Progress Notification Tests")
struct ProgressNotificationTests {
    @Test("Progress notification with message")
    func testProgressNotificationWithMessage() {
        let token = RequestID.string("test-token")
        let progress = 0.5
        let total = 1.0
        let message = "Processing file 5 of 10"

        let notification = ProgressNotification(
            progress: progress,
            progressToken: token,
            total: total,
            message: message
        )

        #expect(notification.params.progress == progress)
        #expect(notification.params.progressToken == token)
        #expect(notification.params.total == total)
        #expect(notification.params.message == message)
    }

    @Test("Progress notification without message")
    func testProgressNotificationWithoutMessage() {
        let token = RequestID.string("test-token")
        let progress = 0.5
        let total = 1.0

        let notification = ProgressNotification(
            progress: progress,
            progressToken: token,
            total: total
        )

        #expect(notification.params.progress == progress)
        #expect(notification.params.progressToken == token)
        #expect(notification.params.total == total)
        #expect(notification.params.message == nil)
    }

    @Test("Progress notification coding")
    func testProgressNotificationCoding() throws {
        let token = RequestID.string("test-token")
        let notification = ProgressNotification(
            progress: 0.5,
            progressToken: token,
            total: 1.0,
            message: "Processing"
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(notification)
        guard let decoded = try? decoder.decode(ProgressNotification.self, from: data) else {
            Issue.record("Failed to decode ProgressNotification")
            return
        }

        #expect(decoded.params.progress == notification.params.progress)
        #expect(decoded.params.progressToken == notification.params.progressToken)
        #expect(decoded.params.total == notification.params.total)
        #expect(decoded.params.message == notification.params.message)
    }
}

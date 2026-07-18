import Foundation
import UserNotifications

@MainActor
final class ScrapeNotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ScrapeNotificationManager()

    private let center = UNUserNotificationCenter.current()

    private override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() async {
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func notifyCompletion(searchName: String, documentCount: Int) {
        let content = UNMutableNotificationContent()
        content.title = "sunBEAR scrape complete"
        content.body = "\(searchName): saved \(documentCount) document\(documentCount == 1 ? "" : "s") and Metadata TSV."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "scrape-complete-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        center.add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

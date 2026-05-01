import Foundation

struct DownloadItem: Identifiable, Equatable, Sendable {
    let id: String
    let url: URL
    let displayName: String
    let activityDate: Date
    let fileSize: Int64?
}

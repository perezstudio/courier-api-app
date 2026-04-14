import Foundation

struct ResponseResult {
    var statusCode: Int
    var statusText: String
    var headers: [String: String]
    var body: Data
    var bodyString: String?
    var duration: TimeInterval
    var size: Int
}

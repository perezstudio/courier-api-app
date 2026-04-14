import Foundation

final class RequestExecutor {
    private var currentTask: URLSessionDataTask?

    var isSending: Bool {
        currentTask != nil
    }

    func execute(
        method: String,
        urlString: String,
        headers: [(key: String, value: String)],
        bodyType: String?,
        bodyContent: String?
    ) async throws -> ResponseResult {
        guard let url = URL(string: urlString) else {
            throw RequestError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 30

        // Set headers
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.key)
        }

        // Set body
        if let bodyType, let bodyContent, !bodyContent.isEmpty {
            switch bodyType {
            case "JSON":
                request.httpBody = bodyContent.data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            case "XML":
                request.httpBody = bodyContent.data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/xml", forHTTPHeaderField: "Content-Type")
                }
            case "URL Encoded":
                request.httpBody = bodyContent.data(using: .utf8)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
                }
            case "GraphQL":
                // Wrap in JSON: { "query": "..." }
                let payload = ["query": bodyContent]
                request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
                if request.value(forHTTPHeaderField: "Content-Type") == nil {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                }
            default:
                break
            }
        }

        let startTime = CFAbsoluteTimeGetCurrent()

        let (data, response) = try await URLSession.shared.data(for: request)

        let duration = CFAbsoluteTimeGetCurrent() - startTime

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RequestError.notHTTPResponse
        }

        var responseHeaders: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            if let k = key as? String, let v = value as? String {
                responseHeaders[k] = v
            }
        }

        let bodyString: String? = {
            // Try to pretty-print JSON
            let contentType = responseHeaders["Content-Type"] ?? ""
            if contentType.contains("json") || contentType.contains("javascript") {
                if let json = try? JSONSerialization.jsonObject(with: data),
                   let pretty = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
                   let str = String(data: pretty, encoding: .utf8) {
                    return str
                }
            }
            return String(data: data, encoding: .utf8)
        }()

        return ResponseResult(
            statusCode: httpResponse.statusCode,
            statusText: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode),
            headers: responseHeaders,
            body: data,
            bodyString: bodyString,
            duration: duration,
            size: data.count
        )
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
    }
}

enum RequestError: LocalizedError {
    case invalidURL
    case notHTTPResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid URL"
        case .notHTTPResponse: return "Response is not HTTP"
        }
    }
}

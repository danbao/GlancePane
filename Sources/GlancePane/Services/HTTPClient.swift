import Foundation

protocol HTTPClient: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

final class URLSessionHTTPClient: HTTPClient {
    private let session: URLSession

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

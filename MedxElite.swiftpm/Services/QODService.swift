import Foundation

public actor QODService {
    public static let shared = QODService()

    private init() {}

    public func fetchQuestionOfTheDay() async throws -> QODData {
        guard let url = URL(string: FirebaseConfig.qodUrl) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let resp = try JSONDecoder().decode(QODResponse.self, from: data)
        guard let qod = resp.data else {
            throw URLError(.cannotParseResponse)
        }

        return qod
    }
}

import Foundation
import Combine

struct BackendHabit: Decodable, Identifiable {
    let id: Int64
    let title: String
    let checksByDate: [String: Bool]

    var completedDayKeys: [String] {
        checksByDate
            .filter { $0.value }
            .map(\.key)
            .sorted()
    }
}

struct AccountabilityDashboard: Decodable {
    let profile: Profile
    let level: Level
    let match: MentorMatch?
    let menteeDashboard: MenteeDashboard
    let mentorDashboard: MentorDashboard
    let mentorship: MentorshipStatus?
    let rewards: Rewards
    let weeklyChallenge: WeeklyChallenge
    let social: SocialDashboard?
    let feed: [SocialPost]
    let notifications: [Notification]

    struct Profile: Decodable {
        let userId: Int64
        let username: String?
        let email: String
        let displayName: String
        let avatarUrl: String?
        let timezone: String
        let language: String
        let goals: String
    }

    struct Level: Decodable {
        let name: String
        let weeklyConsistencyPercent: Int
        let accountabilityScore: Int
        let mentorEligible: Bool
        let needsMentor: Bool
        let note: String
    }

    struct MentorMatch: Decodable {
        let id: Int64
        let status: String
        let mentor: UserSummary
        let mentee: UserSummary
        let matchScore: Int
        let reasons: [String]
    }

    struct UserSummary: Decodable {
        let userId: Int64
        let displayName: String
        let timezone: String
        let language: String
        let goals: String
        let weeklyConsistencyPercent: Int
    }

    struct MenteeDashboard: Decodable {
        let mentorTip: String
        let missedHabitsToday: Int
        let progressScore: Int
        let messages: [Message]
    }

    struct MentorDashboard: Decodable {
        let activeMenteeCount: Int
        let mentees: [MenteeSummary]
    }

    struct MentorshipStatus: Decodable {
        let canFindMentor: Bool
        let hasMentor: Bool
        let canChangeMentor: Bool
        let lockedUntil: String?
        let lockDaysRemaining: Int
        let message: String
    }

    struct MenteeSummary: Decodable, Identifiable {
        var id: Int64 { matchId }

        let matchId: Int64
        let userId: Int64
        let displayName: String
        let missedHabitsToday: Int
        let weeklyConsistencyPercent: Int
        let suggestedAction: String
    }

    struct Rewards: Decodable {
        let xp: Int
        let coins: Int
        let badges: [String]
    }

    struct WeeklyChallenge: Decodable {
        let title: String
        let description: String
        let completedPerfectDays: Int
        let targetPerfectDays: Int
        let rank: Int
        let leaderboard: [LeaderboardEntry]
    }

    struct LeaderboardEntry: Decodable, Identifiable {
        var id: String { "\(displayName)-\(score)-\(currentUser)" }

        let displayName: String
        let score: Int
        let currentUser: Bool
    }

    struct SocialPost: Decodable, Identifiable {
        let id: Int64
        let author: String
        let message: String
        let createdAt: String
    }

    struct SocialDashboard: Decodable {
        let friendCount: Int
        let updates: [SocialActivity]
        let suggestions: [FriendSummary]
    }

    struct SocialActivity: Decodable, Identifiable {
        let id: String
        let userId: Int64
        let displayName: String
        let message: String
        let weeklyConsistencyPercent: Int
        let progressPercent: Int
        let kind: String
        let createdAt: String?
    }

    struct FriendSummary: Decodable, Identifiable {
        var id: Int64 { userId }

        let userId: Int64
        let displayName: String
        let weeklyConsistencyPercent: Int
        let progressPercent: Int
        let goals: String
    }

    struct Message: Decodable, Identifiable {
        let id: Int64
        let senderId: Int64
        let senderName: String
        let message: String
        let nudge: Bool
        let createdAt: String
    }

    struct Notification: Decodable, Identifiable {
        var id: String { "\(type)-\(title)" }

        let title: String
        let body: String
        let type: String
    }
}

@MainActor
final class HabitBackendStore: ObservableObject {
    @Published private(set) var token: String?
    @Published var dashboard: AccountabilityDashboard?
    @Published var isSyncing = false
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    private let client = HabitBackendClient()
    private let tokenKey = "habitTracker.localhost.token"

    var isAuthenticated: Bool {
        token != nil
    }

    init() {
        token = UserDefaults.standard.string(forKey: tokenKey)
    }

    func signIn(username: String, password: String) async {
        await authenticate(username: username, email: nil, password: password, avatarURL: nil, mode: .login)
    }

    func register(username: String, email: String, password: String, avatarURL: String) async {
        await authenticate(username: username, email: email, password: password, avatarURL: avatarURL, mode: .register)
    }

    func signOut() {
        clearSession()
    }

    func listHabits() async throws -> [BackendHabit] {
        do {
            return try await client.listHabits(token: requireToken())
        } catch {
            handleAuthenticatedRequestError(error)
            throw error
        }
    }

    func createHabit(title: String) async throws -> BackendHabit {
        do {
            return try await client.createHabit(title: title, token: requireToken())
        } catch {
            handleAuthenticatedRequestError(error)
            throw error
        }
    }

    func setCheck(habitID: Int64, dateKey: String, done: Bool) async throws {
        do {
            _ = try await client.setCheck(habitID: habitID, dateKey: dateKey, done: done, token: requireToken())
        } catch {
            handleAuthenticatedRequestError(error)
            throw error
        }
    }

    func deleteHabit(habitID: Int64) async throws {
        do {
            try await client.deleteHabit(habitID: habitID, token: requireToken())
        } catch {
            handleAuthenticatedRequestError(error)
            throw error
        }
    }

    func refreshDashboard() async {
        guard let token else { return }

        do {
            dashboard = try await client.dashboard(token: token)
        } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    func assignMentor() async {
        guard let token else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            dashboard = try await client.assignMentor(token: token)
            statusMessage = "Mentor match updated"
            errorMessage = nil
        } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    func sendMenteeMessage(matchId: Int64, message: String) async {
        guard let token else { return }
        do {
            dashboard = try await client.sendMenteeMessage(matchId: matchId, message: message, token: token)
        } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    func requestFriend(userID: Int64) async {
        guard let token else { return }

        isSyncing = true
        defer { isSyncing = false }

        do {
            dashboard = try await client.requestFriend(friendUserID: userID, token: token)
            statusMessage = "Friend added"
            errorMessage = nil
        } catch {
            handleAuthenticatedRequestError(error)
        }
    }

    private enum AuthMode {
        case login
        case register
    }

    private func authenticate(username: String, email: String?, password: String, avatarURL: String?, mode: AuthMode) async {
        isSyncing = true
        defer { isSyncing = false }

        do {
            let issuedToken: String
            switch mode {
            case .login:
                issuedToken = try await client.login(username: username, password: password)
            case .register:
                issuedToken = try await client.register(
                    username: username,
                    email: email ?? "",
                    password: password,
                    avatarURL: avatarURL ?? ""
                )
            }

            token = issuedToken
            UserDefaults.standard.set(issuedToken, forKey: tokenKey)
            statusMessage = "Connected to localhost:8080"
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func requireToken() throws -> String {
        guard let token else {
            throw HabitBackendError.notAuthenticated
        }
        return token
    }

    private func handleAuthenticatedRequestError(_ error: Error) {
        if case HabitBackendError.notAuthenticated = error {
            clearSession(errorMessage: error.localizedDescription)
            return
        }

        errorMessage = error.localizedDescription
    }

    private func clearSession(errorMessage: String? = nil) {
        token = nil
        dashboard = nil
        statusMessage = nil
        self.errorMessage = errorMessage
        UserDefaults.standard.removeObject(forKey: tokenKey)
    }
}

private struct HabitBackendClient {
    private let baseURL = URL(string: "http://127.0.0.1:8080")!
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    func login(username: String, password: String) async throws -> String {
        let response: AuthResponse = try await request(
            path: "/api/auth/login",
            method: "POST",
            body: LoginRequest(username: username, password: password)
        )
        return response.token
    }

    func register(username: String, email: String, password: String, avatarURL: String) async throws -> String {
        let response: AuthResponse = try await request(
            path: "/api/auth/register",
            method: "POST",
            body: RegisterRequest(username: username, email: email, password: password, avatarUrl: avatarURL)
        )
        return response.token
    }

    func listHabits(token: String) async throws -> [BackendHabit] {
        try await request(path: "/api/habits", method: "GET", token: token)
    }

    func createHabit(title: String, token: String) async throws -> BackendHabit {
        try await request(
            path: "/api/habits",
            method: "POST",
            token: token,
            body: HabitCreateRequest(title: title)
        )
    }

    func setCheck(habitID: Int64, dateKey: String, done: Bool, token: String) async throws -> BackendHabit {
        try await request(
            path: "/api/habits/\(habitID)/checks/\(dateKey)",
            method: "PUT",
            token: token,
            body: CheckUpdateRequest(done: done)
        )
    }

    func deleteHabit(habitID: Int64, token: String) async throws {
        let _: EmptyResponse = try await request(
            path: "/api/habits/\(habitID)",
            method: "DELETE",
            token: token
        )
    }

    func dashboard(token: String) async throws -> AccountabilityDashboard {
        try await request(path: "/api/accountability/dashboard", method: "GET", token: token)
    }

    func assignMentor(token: String) async throws -> AccountabilityDashboard {
        try await request(path: "/api/accountability/match", method: "POST", token: token)
    }

    func requestFriend(friendUserID: Int64, token: String) async throws -> AccountabilityDashboard {
        try await request(path: "/api/accountability/friends/\(friendUserID)", method: "POST", token: token)
    }

    func sendMenteeMessage(matchId: Int64, message: String, token: String) async throws -> AccountabilityDashboard {
        try await request(
            path: "/api/accountability/matches/\(matchId)/messages",
            method: "POST",
            token: token,
            body: MentorshipMessageRequest(message: message)
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        token: String? = nil
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, bodyData: nil)
    }

    private func request<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String,
        token: String? = nil,
        body: RequestBody
    ) async throws -> Response {
        try await request(path: path, method: method, token: token, bodyData: encoder.encode(body))
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        token: String?,
        bodyData: Data?
    ) async throws -> Response {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw HabitBackendError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HabitBackendError.invalidResponse
            }

            guard (200..<300).contains(httpResponse.statusCode) else {
                if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                    throw HabitBackendError.notAuthenticated
                }

                let message = (try? decoder.decode(ApiErrorResponse.self, from: data).message)
                    ?? HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                throw HabitBackendError.server(message)
            }

            if Response.self == EmptyResponse.self {
                return EmptyResponse() as! Response
            }

            return try decoder.decode(Response.self, from: data)
        } catch let error as HabitBackendError {
            throw error
        } catch {
            throw HabitBackendError.network(error.localizedDescription)
        }
    }

    private struct LoginRequest: Encodable {
        let username: String
        let password: String
    }

    private struct RegisterRequest: Encodable {
        let username: String
        let email: String
        let password: String
        let avatarUrl: String
    }

    private struct AuthResponse: Decodable {
        let token: String
    }

    private struct HabitCreateRequest: Encodable {
        let title: String
    }

    private struct MentorshipMessageRequest: Encodable {
        let message: String
    }

    private struct CheckUpdateRequest: Encodable {
        let done: Bool
    }

    private struct ApiErrorResponse: Decodable {
        let message: String
    }

    private struct EmptyResponse: Decodable {
    }
}

private enum HabitBackendError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case server(String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Session expired. Sign in again to sync with the backend."
        case .invalidResponse:
            return "The backend returned an invalid response."
        case .server(let message):
            return message
        case .network(let message):
            return "Could not reach localhost:8080. \(message)"
        }
    }
}

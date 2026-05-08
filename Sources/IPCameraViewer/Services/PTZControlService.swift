import CryptoKit
import Foundation
import Observation

enum PTZCommand: String, CaseIterable {
    case up = "Up"
    case down = "Down"
    case left = "Left"
    case right = "Right"
    case leftUp = "LeftUp"
    case rightUp = "RightUp"
    case leftDown = "LeftDown"
    case rightDown = "RightDown"
    case zoomIn = "ZoomTele"
    case zoomOut = "ZoomWide"
}

private struct PTZArguments {
    let arg1: Int
    let arg2: Int
    let arg3: Int
}

private struct PTZEndpoint {
    let scheme: String
    let host: String
    let port: Int?
}

enum PTZAction: String {
    case start
    case stop
}

@Observable
@MainActor
final class PTZControlModel {
    private(set) var status: String?

    private let service = PTZControlService()

    func start(_ command: PTZCommand, camera: Camera) {
        guard camera.isPTZEnabled else { return }

        status = nil
        Task {
            do {
                try await service.send(.start, command: command, camera: camera)
                status = nil
                AppLoggers.streams.info("Started PTZ command \(command.rawValue, privacy: .public)")
            } catch {
                status = error.localizedDescription
                AppLoggers.streams.error("PTZ start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop(_ command: PTZCommand, camera: Camera) {
        guard camera.isPTZEnabled else { return }

        Task {
            do {
                try await service.send(.stop, command: command, camera: camera)
                status = nil
                AppLoggers.streams.info("Stopped PTZ command \(command.rawValue, privacy: .public)")
            } catch {
                status = error.localizedDescription
                AppLoggers.streams.error("PTZ stop failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

enum PTZControlError: LocalizedError {
    case invalidCameraAddress
    case missingCredentials
    case unavailable(String)
    case rejected(Int, String)
    case rpcRejected(String)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidCameraAddress:
            return "PTZ needs a valid camera host."
        case .missingCredentials:
            return "PTZ needs the camera username and password."
        case .unavailable(let message):
            return message
        case .rejected(let statusCode, let body):
            if statusCode == 400 {
                if body.isEmpty {
                    return "PTZ was rejected with HTTP 400. This camera may not support PTZ, or the PTZ channel/HTTP port is different."
                }
                return "PTZ was rejected with HTTP 400: \(body)"
            }
            if body.isEmpty {
                return "The camera rejected the PTZ command with HTTP \(statusCode)."
            }
            return "The camera rejected PTZ with HTTP \(statusCode): \(body)"
        case .rpcRejected(let message):
            return "PTZ RPC failed: \(message)"
        case .emptyResponse:
            return "The camera did not answer the PTZ command."
        }
    }
}

struct PTZControlService {
    func send(_ action: PTZAction, command: PTZCommand, camera: Camera) async throws {
        let username = camera.username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = camera.resolvedPassword
        guard !username.isEmpty, !password.isEmpty else {
            throw PTZControlError.missingCredentials
        }

        do {
            try await sendRPC(action, command: command, camera: camera, username: username, password: password)
            return
        } catch {
            AppLoggers.streams.debug("PTZ RPC path failed, trying CGI fallback: \(error.localizedDescription, privacy: .public)")
        }

        let delegate = PTZURLSessionDelegate(username: username, password: password)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }

        var lastRejection: PTZControlError?
        for channel in candidateChannels(for: camera) {
            for arguments in candidateArguments(for: command, action: action, speed: camera.ptzSpeed) {
                guard let url = controlURL(
                    action: action,
                    command: command,
                    channel: channel,
                    arguments: arguments,
                    camera: camera
                ) else {
                    throw PTZControlError.invalidCameraAddress
                }

                var request = URLRequest(url: url)
                request.timeoutInterval = 3

                AppLoggers.streams.debug("PTZ request: \(redacted(url), privacy: .public)")
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw PTZControlError.emptyResponse
                }

                if (200..<300).contains(httpResponse.statusCode) {
                    return
                }

                let responseBody = trimmedBody(from: data)
                AppLoggers.streams.error("PTZ rejected \(httpResponse.statusCode, privacy: .public) for \(redacted(url), privacy: .public): \(responseBody, privacy: .public)")
                lastRejection = .rejected(httpResponse.statusCode, responseBody)
                if httpResponse.statusCode != 400 {
                    throw PTZControlError.rejected(httpResponse.statusCode, responseBody)
                }
            }
        }

        if case .rejected(400, let body) = lastRejection,
           let diagnostic = await ptzUnavailableDiagnostic(responseBody: body, camera: camera, session: session) {
            throw PTZControlError.unavailable(diagnostic)
        }

        throw lastRejection ?? PTZControlError.emptyResponse
    }

    private func controlURL(
        action: PTZAction,
        command: PTZCommand,
        channel: Int,
        arguments: PTZArguments,
        camera: Camera
    ) -> URL? {
        guard let endpoint = ptzEndpoint(for: camera) else { return nil }

        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = "/cgi-bin/ptz.cgi"
        components.queryItems = [
            URLQueryItem(name: "action", value: action.rawValue),
            URLQueryItem(name: "channel", value: "\(channel)"),
            URLQueryItem(name: "code", value: command.rawValue),
            URLQueryItem(name: "arg1", value: "\(arguments.arg1)"),
            URLQueryItem(name: "arg2", value: "\(arguments.arg2)"),
            URLQueryItem(name: "arg3", value: "\(arguments.arg3)")
        ]
        return components.url
    }

    private func sendRPC(
        _ action: PTZAction,
        command: PTZCommand,
        camera: Camera,
        username: String,
        password: String
    ) async throws {
        guard let endpoint = ptzEndpoint(for: camera) else {
            throw PTZControlError.invalidCameraAddress
        }

        let session = URLSession(configuration: .ephemeral)
        defer {
            session.invalidateAndCancel()
        }

        let loginChallenge = try await rpcRequest(
            RPCLoginRequest.challenge(username: username),
            endpoint: endpoint,
            path: "/RPC2_Login",
            session: session
        )

        guard let challengeSession = loginChallenge.session,
              let realm = loginChallenge.params?.realm,
              let random = loginChallenge.params?.random else {
            throw PTZControlError.rpcRejected(loginChallenge.error?.message ?? "Login challenge was not returned.")
        }

        let passwordHash = Self.rpcPasswordHash(username: username, realm: realm, random: random, password: password)
        let loginResponse = try await rpcRequest(
            RPCLoginRequest.login(username: username, passwordHash: passwordHash, session: challengeSession),
            endpoint: endpoint,
            path: "/RPC2_Login",
            session: session
        )

        guard loginResponse.result == true, let rpcSession = loginResponse.session ?? loginChallenge.session else {
            throw PTZControlError.rpcRejected(loginResponse.error?.message ?? "Login failed.")
        }

        var lastError: String?
        for channel in candidateRPCChannels(for: camera) {
            let response = try await rpcRequest(
                RPCPTZRequest(
                    id: 10,
                    method: "ptz.\(action.rawValue)",
                    params: RPCPTZParams(
                        channel: channel,
                        command: command,
                        arguments: rpcArguments(for: command, speed: camera.ptzSpeed)
                    ),
                    session: rpcSession
                ),
                endpoint: endpoint,
                path: "/RPC2",
                session: session
            )

            if response.result == true {
                return
            }

            lastError = response.error?.message ?? "Channel \(channel) rejected the command."
        }

        throw PTZControlError.rpcRejected(lastError ?? "The camera rejected the RPC PTZ command.")
    }

    private func rpcRequest<Request: Encodable>(
        _ requestBody: Request,
        endpoint: PTZEndpoint,
        path: String,
        session: URLSession
    ) async throws -> RPCResponse {
        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = path

        guard let url = components.url else {
            throw PTZControlError.invalidCameraAddress
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 4
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PTZControlError.emptyResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw PTZControlError.rejected(httpResponse.statusCode, trimmedBody(from: data))
        }

        return try JSONDecoder().decode(RPCResponse.self, from: data)
    }

    private static func rpcPasswordHash(username: String, realm: String, random: String, password: String) -> String {
        let first = md5Hex("\(username):\(realm):\(password)")
        return md5Hex("\(username):\(random):\(first)")
    }

    private static func md5Hex(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }

    private func ptzUnavailableDiagnostic(
        responseBody: String,
        camera: Camera,
        session: URLSession
    ) async -> String? {
        guard responseBody.localizedCaseInsensitiveContains("bad request") else {
            return nil
        }

        let channels = candidateChannels(for: camera)
        var ptzStatusRejected = false
        for channel in channels {
            guard let url = cgiURL(path: "/cgi-bin/ptz.cgi", queryItems: [
                URLQueryItem(name: "action", value: "getStatus"),
                URLQueryItem(name: "channel", value: "\(channel)")
            ], camera: camera) else {
                continue
            }

            if await httpStatus(for: url, session: session) == 400 {
                ptzStatusRejected = true
                break
            }
        }

        var cameraCGIWorks = false
        for channel in channels {
            guard let url = cgiURL(path: "/cgi-bin/devVideoInput.cgi", queryItems: [
                URLQueryItem(name: "action", value: "getCaps"),
                URLQueryItem(name: "channel", value: "\(channel)")
            ], camera: camera) else {
                continue
            }

            if await httpStatus(for: url, session: session) == 200 {
                cameraCGIWorks = true
                break
            }
        }

        guard ptzStatusRejected && cameraCGIWorks else {
            return nil
        }

        return "PTZ is likely unavailable on this camera. It authenticated successfully, but the camera returned Bad Request for PTZ status and movement."
    }

    private func cgiURL(path: String, queryItems: [URLQueryItem], camera: Camera) -> URL? {
        guard let endpoint = ptzEndpoint(for: camera) else { return nil }

        var components = URLComponents()
        components.scheme = endpoint.scheme
        components.host = endpoint.host
        components.port = endpoint.port
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    private func ptzEndpoint(for camera: Camera) -> PTZEndpoint? {
        guard let url = camera.url,
              let host = url.host(percentEncoded: false) else {
            return nil
        }

        let scheme = url.scheme?.lowercased() == "https" ? "https" : "http"
        let defaultPort = scheme == "https" ? 443 : 80
        let port: Int
        if scheme == "https", camera.ptzPort == 80 {
            port = url.port ?? defaultPort
        } else {
            port = camera.ptzPort
        }

        return PTZEndpoint(
            scheme: scheme,
            host: host,
            port: port == defaultPort ? nil : port
        )
    }

    private func httpStatus(for url: URL, session: URLSession) async -> Int? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode
        } catch {
            return nil
        }
    }

    private func trimmedBody(from data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .prefix(160)
            .description ?? ""
    }

    private func redacted(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let hasPassword = components?.password != nil
        if components?.user != nil {
            components?.user = "user"
            components?.password = hasPassword ? "password" : nil
        }
        return components?.url?.absoluteString ?? url.absoluteString
    }

    private func candidateChannels(for camera: Camera) -> [Int] {
        var channels = [camera.ptzChannel]
        if camera.ptzChannel > 0 {
            channels.append(camera.ptzChannel - 1)
        }
        return Array(Set(channels)).sorted { $0 > $1 }
    }

    private func candidateRPCChannels(for camera: Camera) -> [Int] {
        var channels = [max(camera.ptzChannel - 1, 0), camera.ptzChannel]
        channels.append(0)
        return Array(Set(channels)).sorted()
    }

    private func rpcArguments(for command: PTZCommand, speed: Int) -> PTZArguments {
        let speed = min(max(speed, 1), 8)
        switch command {
        case .up:
            return PTZArguments(arg1: 0, arg2: speed, arg3: 0)
        case .down:
            return PTZArguments(arg1: 0, arg2: speed, arg3: 0)
        case .left:
            return PTZArguments(arg1: speed, arg2: 0, arg3: 0)
        case .right:
            return PTZArguments(arg1: speed, arg2: 0, arg3: 0)
        case .leftUp, .rightUp, .leftDown, .rightDown:
            return PTZArguments(arg1: speed, arg2: speed, arg3: 0)
        case .zoomIn, .zoomOut:
            return PTZArguments(arg1: 0, arg2: 0, arg3: 0)
        }
    }

    private func candidateArguments(for command: PTZCommand, action: PTZAction, speed: Int) -> [PTZArguments] {
        guard action == .start else {
            return [PTZArguments(arg1: 0, arg2: 0, arg3: 0)]
        }

        let speed = min(max(speed, 1), 8)
        switch command {
        case .up, .down:
            return [PTZArguments(arg1: 0, arg2: speed, arg3: 0)]
        case .left, .right:
            return [
                PTZArguments(arg1: 0, arg2: speed, arg3: 0),
                PTZArguments(arg1: speed, arg2: 0, arg3: 0)
            ]
        case .leftUp, .rightUp, .leftDown, .rightDown:
            return [
                PTZArguments(arg1: speed, arg2: speed, arg3: 0),
                PTZArguments(arg1: 0, arg2: speed, arg3: 0)
            ]
        case .zoomIn, .zoomOut:
            return [PTZArguments(arg1: 0, arg2: 0, arg3: 0)]
        }
    }
}

private struct RPCResponse: Decodable {
    let result: Bool?
    let params: RPCResponseParams?
    let error: RPCError?
    let session: String?
}

private struct RPCResponseParams: Decodable {
    let realm: String?
    let random: String?
}

private struct RPCError: Decodable {
    let message: String
}

private struct RPCLoginRequest: Encodable {
    let method = "global.login"
    let params: RPCLoginParams
    let id: Int
    let session: String?

    static func challenge(username: String) -> RPCLoginRequest {
        RPCLoginRequest(
            params: RPCLoginParams(
                userName: username,
                password: "",
                clientType: "Web3.0",
                authorityType: nil,
                passwordType: nil
            ),
            id: 1,
            session: nil
        )
    }

    static func login(username: String, passwordHash: String, session: String) -> RPCLoginRequest {
        RPCLoginRequest(
            params: RPCLoginParams(
                userName: username,
                password: passwordHash,
                clientType: "Web3.0",
                authorityType: "Default",
                passwordType: "Default"
            ),
            id: 2,
            session: session
        )
    }
}

private struct RPCLoginParams: Encodable {
    let userName: String
    let password: String
    let clientType: String
    let authorityType: String?
    let passwordType: String?
}

private struct RPCPTZRequest: Encodable {
    let id: Int
    let method: String
    let params: RPCPTZParams
    let session: String
}

private struct RPCPTZParams: Encodable {
    let channel: Int
    let code: String
    let arg1: Int
    let arg2: Int
    let arg3: Int

    init(channel: Int, command: PTZCommand, arguments: PTZArguments) {
        self.channel = channel
        code = command.rawValue
        arg1 = arguments.arg1
        arg2 = arguments.arg2
        arg3 = arguments.arg3
    }

    enum CodingKeys: String, CodingKey {
        case channel
        case code
        case arg1
        case arg2
        case arg3
        case arg4
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(channel, forKey: .channel)
        try container.encode(code, forKey: .code)
        try container.encode(arg1, forKey: .arg1)
        try container.encode(arg2, forKey: .arg2)
        try container.encode(arg3, forKey: .arg3)
        try container.encodeNil(forKey: .arg4)
    }
}

private final class PTZURLSessionDelegate: NSObject, URLSessionTaskDelegate {
    private let username: String
    private let password: String

    init(username: String, password: String) {
        self.username = username
        self.password = password
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        switch challenge.protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic,
             NSURLAuthenticationMethodHTTPDigest,
             NSURLAuthenticationMethodDefault:
            let credential = URLCredential(
                user: username,
                password: password,
                persistence: .forSession
            )
            return (.useCredential, credential)
        default:
            return (.performDefaultHandling, nil)
        }
    }
}

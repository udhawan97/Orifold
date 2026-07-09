import Foundation

/// Check-only update transport: asks the GitHub Releases API for the latest *stable*
/// release and compares its tag to the running version. This is the transport that ships
/// before Sparkle — it works today under the sandbox because it makes only an outbound
/// HTTPS GET (the `network.client` entitlement, already granted) and never tries to
/// download or replace the bundle.
///
/// `releases/latest` deliberately excludes prereleases, so the `Orifold-latest` dev-channel
/// prerelease is ignored and only tagged `v*` / `release-v*` releases are ever offered —
/// which is also what keeps the check from ever proposing a downgrade.
struct GitHubReleaseTransport: UpdateTransport {
    /// `owner/repo` from the release URLs the pipeline already publishes.
    static let repository = "udhawan97/Orifold"

    private let session: URLSession
    private let defaults: UserDefaults
    private let repository: String

    init(session: URLSession = .shared, defaults: UserDefaults = .standard, repository: String = GitHubReleaseTransport.repository) {
        self.session = session
        self.defaults = defaults
        self.repository = repository
    }

    private var latestReleaseURL: URL {
        URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    private var etagDefaultsKey: String { "orifoldUpdateLatestETag" }

    func checkForUpdate(currentVersion: UpdateVersion) async throws -> UpdateCheckOutcome {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Orifold", forHTTPHeaderField: "User-Agent")
        // Conditional GET so unchanged releases don't count against the API rate limit.
        if let etag = defaults.string(forKey: etagDefaultsKey) {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw UpdateTransportError.badResponse
        }

        // 304 → nothing changed since the last check; the cached answer is "up to date"
        // relative to whatever we last saw, so treat it as up to date.
        if http.statusCode == 304 { return .upToDate }
        guard (200...299).contains(http.statusCode) else {
            throw UpdateTransportError.httpStatus(http.statusCode)
        }
        if let etag = http.value(forHTTPHeaderField: "ETag") {
            defaults.set(etag, forKey: etagDefaultsKey)
        }

        let release: GitHubRelease
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            release = try decoder.decode(GitHubRelease.self, from: data)
        } catch {
            throw UpdateTransportError.decoding(String(describing: error))
        }

        guard let latest = UpdateVersion(string: release.tagName) else {
            throw UpdateTransportError.unparseableTag(release.tagName)
        }
        guard latest > currentVersion else { return .upToDate }

        // Prefer the DMG asset's size for the download chip; fall back to the zip.
        let asset = release.assets.first { $0.name.hasSuffix(".dmg") }
            ?? release.assets.first { $0.name.hasSuffix(".zip") }

        return .available(AvailableUpdate(
            version: latest.description,
            currentVersion: currentVersion.description,
            releaseNotesURL: release.htmlURL,
            downloadPageURL: URL(string: "https://github.com/\(repository)/releases/latest"),
            publishedAt: release.publishedAt,
            assetSizeBytes: asset?.size
        ))
    }
}

enum UpdateTransportError: Error, Equatable {
    case badResponse
    case httpStatus(Int)
    case decoding(String)
    case unparseableTag(String)
}

/// Minimal slice of the GitHub Releases API payload we actually read.
private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlURL: URL?
    let publishedAt: Date?
    let assets: [Asset]

    struct Asset: Decodable {
        let name: String
        let size: Int
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
        case assets
    }
}

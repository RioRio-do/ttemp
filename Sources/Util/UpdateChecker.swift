import Foundation

/// 「最新版を確認…」の結果。表示文言は呼び出し側（UI）が組み立てる。
enum UpdateCheckResult: Equatable {
    /// 現在のバージョンが最新（またはそれより新しい）
    case upToDate(current: String)
    case updateAvailable(latest: String, url: URL)
    /// リリースが1件もない・ネットワーク不通など。付随文字列はログ／詳細表示用
    case failed(String)
}

/// GitHub Releases の最新リリースと自分のバージョンを比べる（Sparkle 等を入れる前の
/// 最小の更新導線。自動ダウンロードはせず、リリースページへ誘導するだけ）。
enum UpdateChecker {
    static func check(currentVersion: String = AppInfo.version,
                      completion: @escaping (UpdateCheckResult) -> Void) {
        var request = URLRequest(url: AppInfo.latestReleaseAPIURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            let result = Self.parseResponse(data: data,
                                            response: response,
                                            error: error,
                                            currentVersion: currentVersion)
            DispatchQueue.main.async { completion(result) }
        }
        task.resume()
    }

    /// レスポンス解釈。ネットワークに触れない純粋関数（テスト対象）。
    static func parseResponse(data: Data?,
                              response: URLResponse?,
                              error: Error?,
                              currentVersion: String) -> UpdateCheckResult {
        if let error {
            return .failed(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            // 404 はリリース未作成（またはリポジトリ非公開）のときに返る
            return .failed("HTTP \(http.statusCode)")
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            return .failed("unexpected response")
        }
        let url = (json["html_url"] as? String).flatMap(URL.init(string:)) ?? AppInfo.releasesURL
        if isNewer(tag, than: currentVersion) {
            return .updateAvailable(latest: tag, url: url)
        }
        return .upToDate(current: currentVersion)
    }

    /// "v1.2.3" / "1.2.3" 形式を数値の列として比較する。桁が欠けた側は 0 とみなす。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(of: candidate)
        let b = components(of: current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(of version: String) -> [Int] {
        version
            .drop(while: { $0 == "v" || $0 == "V" })
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

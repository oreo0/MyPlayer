import Foundation

// MARK: - 在线文件信息匹配（网易云音乐优先，QQ 音乐兜底）

struct MatchedInfo {
    var artist: String?
    var album: String?
    var coverData: Data?
    var lyric: String?
}

enum MetadataMatcher {

    static func match(title: String, artist: String) async -> MatchedInfo? {
        var t = title
        var a = artist
        // 文件名常见的 "艺人 - 歌名" 结构
        if a.isEmpty, let range = t.range(of: " - ") {
            a = String(t[..<range.lowerBound])
            t = String(t[range.upperBound...])
        }
        t = clean(t)
        a = clean(a)
        let keyword = [a, t].filter { !$0.isEmpty }.joined(separator: " ")
        guard !keyword.isEmpty else { return nil }

        if let info = await netEase(keyword: keyword) { return info }
        if let info = await qq(keyword: keyword) { return info }
        return nil
    }

    /// 清理文件名里的装饰性内容：(HQ) [Live] 【无损】 01. 等
    private static func clean(_ s: String) -> String {
        var out = s
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]", "（[^）]*）", "【[^】]*】"] {
            out = out.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        out = out.replacingOccurrences(of: "^\\d+[\\s._-]+", with: "", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s{2,}", with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func httpData(_ request: URLRequest) async -> Data? {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode) else { return nil }
            return data
        } catch {
            return nil
        }
    }

    private static func browserRequest(url: URL, referer: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
                         forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        return request
    }

    // MARK: 网易云音乐

    private static func netEase(keyword: String) async -> MatchedInfo? {
        // 1. 搜索文件
        var request = browserRequest(url: URL(string: "https://music.163.com/api/search/get/web")!,
                                     referer: "https://music.163.com")
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let escaped = keyword.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        request.httpBody = "s=\(escaped)&type=1&offset=0&limit=1".data(using: .utf8)

        guard let raw = await httpData(request),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let result = json["result"] as? [String: Any],
              let songs = result["songs"] as? [[String: Any]],
              let song = songs.first else { return nil }

        let songID = song["id"] as? Int ?? 0
        guard songID > 0 else { return nil }

        var info = MatchedInfo()
        info.artist = (song["artists"] as? [[String: Any]])?.first?["name"] as? String
        let album = song["album"] as? [String: Any]
        info.album = album?["name"] as? String

        // 2. 歌词
        if let lyric = await netEaseLyric(songID: songID), !lyric.isEmpty {
            info.lyric = lyric
        }

        // 3. 封面（搜索结果通常不含大图，需查文件详情）
        var picURL = album?["picUrl"] as? String
        if picURL == nil {
            picURL = await netEaseCoverURL(songID: songID)
        }
        if let picURL, let url = URL(string: picURL) {
            info.coverData = await httpData(browserRequest(url: url, referer: "https://music.163.com"))
        }
        return info
    }

    private static func netEaseLyric(songID: Int) async -> String? {
        var comps = URLComponents(string: "https://music.163.com/api/song/lyric")!
        comps.queryItems = [
            .init(name: "id", value: String(songID)),
            .init(name: "lv", value: "1"),
            .init(name: "kv", value: "1"),
            .init(name: "tv", value: "-1")
        ]
        guard let url = comps.url else { return nil }
        guard let raw = await httpData(browserRequest(url: url, referer: "https://music.163.com")),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let lrc = json["lrc"] as? [String: Any] else { return nil }
        return lrc["lyric"] as? String
    }

    private static func netEaseCoverURL(songID: Int) async -> String? {
        var comps = URLComponents(string: "https://music.163.com/api/song/detail")!
        comps.queryItems = [
            .init(name: "id", value: String(songID)),
            .init(name: "ids", value: "[\(songID)]")
        ]
        guard let url = comps.url else { return nil }
        guard let raw = await httpData(browserRequest(url: url, referer: "https://music.163.com")),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let songs = json["songs"] as? [[String: Any]],
              let first = songs.first,
              let album = first["album"] as? [String: Any] else { return nil }
        return album["picUrl"] as? String
    }

    // MARK: QQ 音乐

    private static func qq(keyword: String) async -> MatchedInfo? {
        // 1. 搜索
        var comps = URLComponents(string: "https://c.y.qq.com/soso/fcgi-bin/client_search_cp")!
        comps.queryItems = [
            .init(name: "w", value: keyword),
            .init(name: "format", value: "json"),
            .init(name: "t", value: "0"),
            .init(name: "n", value: "1")
        ]
        guard let url = comps.url else { return nil }
        guard let raw = await httpData(browserRequest(url: url, referer: "https://y.qq.com")),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let data = json["data"] as? [String: Any],
              let songWrap = data["song"] as? [String: Any],
              let list = songWrap["list"] as? [[String: Any]],
              let song = list.first else { return nil }

        var info = MatchedInfo()
        info.artist = (song["singer"] as? [[String: Any]])?.first?["name"] as? String
        info.album = song["albumname"] as? String
        let songMid = song["songmid"] as? String ?? ""
        let albumMid = song["albummid"] as? String ?? ""

        // 2. 歌词（base64 编码）
        if !songMid.isEmpty, let lyric = await qqLyric(songMid: songMid), !lyric.isEmpty {
            info.lyric = lyric
        }

        // 3. 封面
        if !albumMid.isEmpty,
           let coverURL = URL(string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\(albumMid).jpg") {
            info.coverData = await httpData(browserRequest(url: coverURL, referer: "https://y.qq.com"))
        }
        return info
    }

    private static func qqLyric(songMid: String) async -> String? {
        var comps = URLComponents(string: "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg")!
        comps.queryItems = [
            .init(name: "songmid", value: songMid),
            .init(name: "g_tk", value: "5381"),
            .init(name: "format", value: "json"),
            .init(name: "loginUin", value: "0"),
            .init(name: "hostUin", value: "0"),
            .init(name: "inCharset", value: "utf8"),
            .init(name: "outCharset", value: "utf-8"),
            .init(name: "notice", value: "0"),
            .init(name: "platform", value: "yqq.json"),
            .init(name: "needNewCode", value: "0")
        ]
        guard let url = comps.url else { return nil }
        guard let raw = await httpData(browserRequest(url: url, referer: "https://y.qq.com/portal/player.html")),
              let json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any],
              let base64 = json["lyric"] as? String,
              let data = Data(base64Encoded: base64),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }
}

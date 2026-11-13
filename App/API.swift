import Foundation

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct EventRow: Decodable, Identifiable {
    let slug: String
    let upload_key: String
    let title: String
    let honoree: String
    let event_date: String?
    let sessions: Int?
    var id: String { slug }
}

enum API {
    private static func request(_ path: String) -> URLRequest {
        var r = URLRequest(url: Config.supabaseURL.appendingPathComponent(path))
        r.httpMethod = "POST"
        r.timeoutInterval = 30
        r.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return r
    }

    /// Calls a Postgres function (vb_list_events, vb_create_event, ...).
    static func rpc<T: Decodable>(_ fn: String, _ params: [String: Any], as type: T.Type,
                                  completion: @escaping (Result<T, Error>) -> Void) {
        var r = request("rest/v1/rpc/\(fn)")
        r.httpBody = try? JSONSerialization.data(withJSONObject: params)
        URLSession.shared.dataTask(with: r) { data, resp, err in
            let result: Result<T, Error>
            if let err = err {
                result = .failure(err)
            } else {
                let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
                let body = data ?? Data()
                if (200..<300).contains(code) {
                    do { result = .success(try JSONDecoder().decode(T.self, from: body)) }
                    catch { result = .failure(error) }
                } else {
                    let obj = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
                    let msg = obj?["message"] as? String ?? "HTTP \(code)"
                    result = .failure(APIError(message: msg))
                }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }

    /// Calls the vb-booth edge function. status is 0 when the network failed.
    static func booth(_ body: [String: Any], completion: @escaping (Int, [String: Any]) -> Void) {
        var r = request("functions/v1/vb-booth")
        r.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: r) { data, resp, err in
            let code = err == nil ? ((resp as? HTTPURLResponse)?.statusCode ?? 0) : 0
            let obj = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
            DispatchQueue.main.async { completion(code, obj) }
        }.resume()
    }

    /// Uploads a file to a signed Supabase Storage upload URL.
    static func put(file: URL, to urlString: String, contentType: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else { completion(false); return }
        var r = URLRequest(url: url)
        r.httpMethod = "PUT"
        r.timeoutInterval = 600
        r.setValue(contentType, forHTTPHeaderField: "Content-Type")
        r.setValue("true", forHTTPHeaderField: "x-upsert")
        r.setValue(Config.publishableKey, forHTTPHeaderField: "apikey")
        URLSession.shared.uploadTask(with: r, fromFile: file) { _, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let ok = err == nil && (200..<300).contains(code)
            DispatchQueue.main.async { completion(ok) }
        }.resume()
    }
}

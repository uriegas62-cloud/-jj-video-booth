import Foundation
import UIKit

/// One guest visit: the print image, the optional video message, and where it's at uploading.
struct BoothSession: Codable, Identifiable {
    var code: String
    var createdAt: Date
    var eventSlug: String
    var uploadKey: String
    var eventTitle: String
    var hasVideo: Bool
    var videoSeconds: Double
    var uploaded: Bool
    var pendingEmails: [String]
    var sentEmails: [String]
    var id: String { code }
}

/// Saves every session on the iPad first (so nothing is lost if the venue Wi-Fi drops),
/// then uploads in the background and sends any emails guests typed in.
final class SessionStore: ObservableObject {
    static let shared = SessionStore()

    @Published private(set) var sessions: [BoothSession] = []
    @Published var lastUploadError = ""
    private var busy = false
    private var timer: Timer?
    private let root: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("sessions", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        load()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.processQueue()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.processQueue() }
    }

    // MARK: files
    func dir(_ code: String) -> URL { root.appendingPathComponent(code, isDirectory: true) }
    func photoURL(_ code: String) -> URL { dir(code).appendingPathComponent("photo.jpg") }
    func videoURL(_ code: String) -> URL { dir(code).appendingPathComponent("video.mp4") }
    private func metaURL(_ code: String) -> URL { dir(code).appendingPathComponent("meta.json") }

    func photo(_ code: String) -> UIImage? { UIImage(contentsOfFile: photoURL(code).path) }

    private func load() {
        let fm = FileManager.default
        let dirs = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let dec = JSONDecoder()
        var list: [BoothSession] = []
        for d in dirs {
            if let data = try? Data(contentsOf: d.appendingPathComponent("meta.json")),
               let s = try? dec.decode(BoothSession.self, from: data) {
                list.append(s)
            }
        }
        sessions = list.sorted { $0.createdAt > $1.createdAt }
    }

    private func writeMeta(_ s: BoothSession) {
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: metaURL(s.code), options: .atomic)
        }
    }

    private func update(_ s: BoothSession) {
        writeMeta(s)
        if let i = sessions.firstIndex(where: { $0.code == s.code }) { sessions[i] = s }
    }

    func session(_ code: String) -> BoothSession? { sessions.first { $0.code == code } }

    func sessions(forEvent slug: String) -> [BoothSession] { sessions.filter { $0.eventSlug == slug } }

    var pendingCount: Int { sessions.filter { !$0.uploaded || !$0.pendingEmails.isEmpty }.count }

    // MARK: create
    func newCode() -> String {
        let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
        while true {
            let c = String((0..<8).map { _ in alphabet.randomElement()! })
            if session(c) == nil { return c }
        }
    }

    @discardableResult
    func add(photoJPEG: Data, videoFile: URL?, videoSeconds: Double, settings: BoothSettings) -> BoothSession {
        let code = newCode()
        try? FileManager.default.createDirectory(at: dir(code), withIntermediateDirectories: true)
        try? photoJPEG.write(to: photoURL(code), options: .atomic)
        var hasVideo = false
        if let v = videoFile {
            do {
                try FileManager.default.moveItem(at: v, to: videoURL(code))
                hasVideo = true
            } catch {
                hasVideo = (try? FileManager.default.copyItem(at: v, to: videoURL(code))) != nil
            }
        }
        let s = BoothSession(code: code, createdAt: Date(), eventSlug: settings.eventSlug,
                             uploadKey: settings.uploadKey, eventTitle: settings.eventTitle,
                             hasVideo: hasVideo, videoSeconds: videoSeconds, uploaded: false,
                             pendingEmails: [], sentEmails: [])
        writeMeta(s)
        sessions.insert(s, at: 0)
        processQueue()
        return s
    }

    func queueEmail(_ email: String, for code: String) {
        guard var s = session(code) else { return }
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, !s.pendingEmails.contains(e) else { return }
        s.pendingEmails.append(e)
        update(s)
        processQueue()
    }

    // MARK: queue
    func processQueue() {
        guard !busy else { return }
        guard let next = sessions.reversed().first(where: { !$0.uploaded || !$0.pendingEmails.isEmpty }) else { return }
        busy = true
        if !next.uploaded {
            upload(next) { ok in
                self.busy = false
                if ok, var s = self.session(next.code) {
                    s.uploaded = true
                    self.update(s)
                    self.lastUploadError = ""
                    self.processQueue()
                }
            }
        } else {
            sendEmails(next) { progressed in
                self.busy = false
                if progressed { self.processQueue() }
            }
        }
    }

    private func upload(_ s: BoothSession, done: @escaping (Bool) -> Void) {
        let base: [String: Any] = ["slug": s.eventSlug, "upload_key": s.uploadKey, "code": s.code]
        var prep = base; prep["action"] = "prepare"
        API.booth(prep) { status, j in
            guard status == 200,
                  let pu = j["photo_upload_url"] as? String,
                  let vu = j["video_upload_url"] as? String else {
                self.lastUploadError = (j["error"] as? String) ?? (status == 0 ? "No internet" : "Upload error \(status)")
                done(false); return
            }
            API.put(file: self.photoURL(s.code), to: pu, contentType: "image/jpeg") { ok in
                guard ok else { self.lastUploadError = "Photo upload failed"; done(false); return }
                let finish = {
                    var comp = base
                    comp["action"] = "complete"
                    comp["has_photo"] = true
                    comp["has_video"] = s.hasVideo
                    comp["video_seconds"] = s.videoSeconds
                    API.booth(comp) { st, j2 in
                        if st == 200 { done(true) } else {
                            self.lastUploadError = (j2["error"] as? String) ?? "Finish error \(st)"
                            done(false)
                        }
                    }
                }
                if s.hasVideo {
                    API.put(file: self.videoURL(s.code), to: vu, contentType: "video/mp4") { ok2 in
                        if ok2 { finish() } else { self.lastUploadError = "Video upload failed"; done(false) }
                    }
                } else {
                    finish()
                }
            }
        }
    }

    private func sendEmails(_ s: BoothSession, done: @escaping (Bool) -> Void) {
        guard let email = s.pendingEmails.first else { done(false); return }
        let body: [String: Any] = ["action": "email", "slug": s.eventSlug, "upload_key": s.uploadKey,
                                   "code": s.code, "email": email]
        API.booth(body) { status, j in
            guard var cur = self.session(s.code) else { done(false); return }
            if status == 200 {
                cur.pendingEmails.removeAll { $0 == email }
                cur.sentEmails.append(email)
                self.update(cur)
                done(true)
            } else if (400..<500).contains(status) && status != 404 {
                // bad address or limit reached: drop it so the queue doesn't get stuck
                cur.pendingEmails.removeAll { $0 == email }
                self.update(cur)
                self.lastUploadError = "Email to \(email) failed: \((j["error"] as? String) ?? "\(status)")"
                done(true)
            } else {
                self.lastUploadError = "Email waiting: \((j["error"] as? String) ?? (status == 0 ? "No internet" : "\(status)"))"
                done(false)
            }
        }
    }
}

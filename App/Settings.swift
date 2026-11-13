import Foundation

enum Config {
    static let supabaseURL = URL(string: "https://prwpbaauvwibdtkwvsot.supabase.co")!
    static let publishableKey = "sb_publishable_ozRSk5bR2aPQlgXSGZ-eCA_GtDG6gdw"
    static let defaultGalleryBase = "https://jj-video-booth.netlify.app"
}

/// Everything the operator sets in the hidden settings screen. Saved on the iPad.
final class BoothSettings: ObservableObject {
    static let shared = BoothSettings()
    private let d = UserDefaults.standard

    // Event
    @Published var eventSlug: String { didSet { d.set(eventSlug, forKey: "eventSlug") } }
    @Published var uploadKey: String { didSet { d.set(uploadKey, forKey: "uploadKey") } }
    @Published var eventTitle: String { didSet { d.set(eventTitle, forKey: "eventTitle") } }
    @Published var honoree: String { didSet { d.set(honoree, forKey: "honoree") } }
    @Published var eventDateText: String { didSet { d.set(eventDateText, forKey: "eventDateText") } }
    @Published var adminKey: String { didSet { d.set(adminKey, forKey: "adminKey") } }
    @Published var galleryBase: String { didSet { d.set(galleryBase, forKey: "galleryBase") } }

    // Printer
    @Published var printerURL: String { didSet { d.set(printerURL, forKey: "printerURL") } }
    @Published var printerName: String { didSet { d.set(printerName, forKey: "printerName") } }
    @Published var autoPrint: Bool { didSet { d.set(autoPrint, forKey: "autoPrint") } }
    @Published var copies: Int { didSet { d.set(copies, forKey: "copies") } }
    @Published var allowGuestReprint: Bool { didSet { d.set(allowGuestReprint, forKey: "allowGuestReprint") } }

    // Booth
    @Published var videoSeconds: Int { didSet { d.set(videoSeconds, forKey: "videoSeconds") } }
    @Published var shots: Int { didSet { d.set(shots, forKey: "shots") } }
    @Published var countdownSeconds: Int { didSet { d.set(countdownSeconds, forKey: "countdownSeconds") } }
    @Published var hd1080: Bool { didSet { d.set(hd1080, forKey: "hd1080") } }
    @Published var settingsPin: String { didSet { d.set(settingsPin, forKey: "settingsPin") } }

    private init() {
        eventSlug = d.string(forKey: "eventSlug") ?? ""
        uploadKey = d.string(forKey: "uploadKey") ?? ""
        eventTitle = d.string(forKey: "eventTitle") ?? ""
        honoree = d.string(forKey: "honoree") ?? ""
        eventDateText = d.string(forKey: "eventDateText") ?? ""
        adminKey = d.string(forKey: "adminKey") ?? ""
        galleryBase = d.string(forKey: "galleryBase") ?? Config.defaultGalleryBase
        printerURL = d.string(forKey: "printerURL") ?? ""
        printerName = d.string(forKey: "printerName") ?? ""
        autoPrint = d.object(forKey: "autoPrint") as? Bool ?? true
        copies = d.object(forKey: "copies") as? Int ?? 1
        allowGuestReprint = d.object(forKey: "allowGuestReprint") as? Bool ?? false
        videoSeconds = d.object(forKey: "videoSeconds") as? Int ?? 30
        shots = d.object(forKey: "shots") as? Int ?? 3
        countdownSeconds = d.object(forKey: "countdownSeconds") as? Int ?? 3
        hd1080 = d.object(forKey: "hd1080") as? Bool ?? false
        settingsPin = d.string(forKey: "settingsPin") ?? "2580"
    }

    var hasEvent: Bool { !eventSlug.isEmpty && !uploadKey.isEmpty }
    var honoreeOrGuest: String { honoree.isEmpty ? "the guest of honor" : honoree }

    private var base: String {
        var b = galleryBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return b
    }
    func guestLink(_ code: String) -> String { "\(base)/?s=\(code)" }
    var nightGalleryLink: String { "\(base)/?e=\(eventSlug)" }
    var hostGalleryLink: String { "\(base)/?e=\(eventSlug)&host=1" }
}

import SwiftUI
import AudioToolbox

/// The guest flow: video message -> photos -> print + share.
final class BoothModel: ObservableObject {
    enum Step: Equatable { case attract, videoIntro, videoCountdown, recording, savingVideo, photoIntro, photoCountdown, processing, share }

    @Published var step: Step = .attract
    @Published var countdown = 3
    @Published var elapsed: Double = 0
    @Published var shotIndex = 0
    @Published var flash = false
    @Published var current: BoothSession?
    @Published var printImage: UIImage?
    @Published var printStatus = ""
    @Published var message = ""

    let camera = CameraController()
    let settings = BoothSettings.shared
    let store = SessionStore.shared

    private var shots: [UIImage] = []
    private var videoURL: URL?
    private var videoSeconds: Double = 0
    private var timer: Timer?
    private var idleTimer: Timer?

    // MARK: flow
    func start() {
        reset()
        guard settings.hasEvent else { message = "Booth isn't set up yet"; return }
        step = .videoIntro
    }

    func skipVideo() {
        videoURL = nil
        videoSeconds = 0
        step = .photoIntro
    }

    func beginVideo() {
        runCountdown(.videoCountdown) { self.startRecording() }
    }

    private func startRecording() {
        step = .recording
        elapsed = 0
        let limit = Double(settings.videoSeconds)
        camera.record(maxSeconds: settings.videoSeconds) { url, secs in
            guard self.step == .recording || self.step == .savingVideo else {
                if let url = url { try? FileManager.default.removeItem(at: url) }
                return
            }
            self.timer?.invalidate()
            self.videoURL = url
            self.videoSeconds = secs
            if url == nil { self.message = "The video didn't save — let's still get your photo!" }
            self.step = .photoIntro
        }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { t in
            self.elapsed = min(limit, self.elapsed + 0.1)
            if self.elapsed >= limit { t.invalidate(); self.step = .savingVideo }
        }
    }

    func stopRecording() {
        timer?.invalidate()
        step = .savingVideo
        camera.stopRecording()
    }

    func beginPhotos() {
        message = ""
        shots = []
        shotIndex = 0
        nextShot()
    }

    private func nextShot() {
        runCountdown(.photoCountdown) { self.capture() }
    }

    private func capture() {
        flash = true
        AudioServicesPlaySystemSound(1108)
        camera.capturePhoto { img in
            withAnimation(.easeOut(duration: 0.4)) { self.flash = false }
            if let img = img { self.shots.append(img) }
            self.shotIndex += 1
            if self.shotIndex >= max(1, self.settings.shots) {
                self.finish()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.nextShot() }
            }
        }
    }

    private func finish() {
        guard !shots.isEmpty else {
            message = "The camera missed that one — tap start to try again"
            cleanupVideo()
            step = .attract
            return
        }
        step = .processing
        let shots = self.shots
        let title = settings.eventTitle.isEmpty ? "Thanks for celebrating!" : settings.eventTitle
        let subtitle = settings.eventDateText
        let video = videoURL, secs = videoSeconds
        DispatchQueue.global(qos: .userInitiated).async {
            let img = PrintComposer.compose(shots: shots, title: title, subtitle: subtitle)
            let jpeg = img.jpegData(compressionQuality: 0.9) ?? Data()
            DispatchQueue.main.async {
                let s = self.store.add(photoJPEG: jpeg, videoFile: video, videoSeconds: secs, settings: self.settings)
                self.videoURL = nil
                self.current = s
                self.printImage = img
                self.step = .share
                self.touch()
                if self.settings.autoPrint { self.print(img) } else { self.printStatus = "" }
            }
        }
    }

    func print(_ img: UIImage) {
        printStatus = "Printing your photo…"
        PrinterService.shared.print(img, copies: settings.copies) { ok, msg in
            self.printStatus = ok ? "Printed! Grab it from the printer 🎉" : "Print problem: \(msg)"
        }
    }

    func sendEmail(_ email: String) {
        guard let code = current?.code else { return }
        store.queueEmail(email, for: code)
        touch()
    }

    func done() {
        idleTimer?.invalidate()
        reset()
    }

    func cancel() {
        timer?.invalidate()
        if camera.isRecording { camera.discardRecording() }
        reset()
    }

    /// Keeps the share screen up while the guest is using it; returns to start after 90s idle.
    func touch() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: false) { _ in
            if self.step == .share { self.done() }
        }
    }

    // MARK: helpers
    private func runCountdown(_ s: Step, then: @escaping () -> Void) {
        timer?.invalidate()
        countdown = max(1, settings.countdownSeconds)
        step = s
        AudioServicesPlaySystemSound(1103)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { t in
            self.countdown -= 1
            if self.countdown <= 0 {
                t.invalidate()
                then()
            } else {
                AudioServicesPlaySystemSound(1103)
            }
        }
    }

    private func cleanupVideo() {
        if let v = videoURL { try? FileManager.default.removeItem(at: v) }
        videoURL = nil
    }

    private func reset() {
        timer?.invalidate()
        cleanupVideo()
        shots = []
        shotIndex = 0
        elapsed = 0
        flash = false
        current = nil
        printImage = nil
        printStatus = ""
        message = ""
        step = .attract
    }
}

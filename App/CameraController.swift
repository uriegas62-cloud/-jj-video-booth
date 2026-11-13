import AVFoundation
import SwiftUI
import UIKit

/// Front camera + mic. Records the video message (H.264 .mp4) and takes still photos from the same session.
final class CameraController: NSObject, ObservableObject {
    let session = AVCaptureSession()
    @Published var isReady = false
    @Published var permissionDenied = false

    private let queue = DispatchQueue(label: "jj.camera")
    private let movieOutput = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var configured = false
    private var configuredFor1080: Bool?
    private var movieCompletion: ((URL?, Double) -> Void)?
    private var photoCompletion: ((UIImage?) -> Void)?

    var isRecording: Bool { movieOutput.isRecording }

    func start(hd1080: Bool) {
        AVCaptureDevice.requestAccess(for: .video) { videoOK in
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                guard videoOK else {
                    DispatchQueue.main.async { self.permissionDenied = true }
                    return
                }
                self.queue.async {
                    self.configure(hd1080: hd1080)
                    if !self.session.isRunning { self.session.startRunning() }
                    DispatchQueue.main.async { self.isReady = true }
                }
            }
        }
    }

    /// Re-applies the 720p/1080p choice if it changed in settings.
    func applyQuality(hd1080: Bool) {
        queue.async {
            guard self.configured, self.configuredFor1080 != hd1080, !self.movieOutput.isRecording else { return }
            self.session.beginConfiguration()
            self.setPreset(hd1080: hd1080)
            self.session.commitConfiguration()
            self.configurePhotoDimensions()
        }
    }

    private func setPreset(hd1080: Bool) {
        let wanted: AVCaptureSession.Preset = hd1080 ? .hd1920x1080 : .hd1280x720
        if session.canSetSessionPreset(wanted) { session.sessionPreset = wanted }
        else if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
        configuredFor1080 = hd1080
    }

    private func configure(hd1080: Bool) {
        guard !configured else { return }
        session.beginConfiguration()
        setPreset(hd1080: hd1080)

        if let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video),
           let input = try? AVCaptureDeviceInput(device: cam), session.canAddInput(input) {
            session.addInput(input)
        }
        if let mic = AVCaptureDevice.default(for: .audio),
           let micInput = try? AVCaptureDeviceInput(device: mic), session.canAddInput(micInput) {
            session.addInput(micInput)
        }
        if session.canAddOutput(movieOutput) { session.addOutput(movieOutput) }
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }

        if let c = movieOutput.connection(with: .video) {
            CameraController.portrait(c)
            if movieOutput.availableVideoCodecTypes.contains(.h264) {
                movieOutput.setOutputSettings([AVVideoCodecKey: AVVideoCodecType.h264], for: c)
            }
        }
        if let c = photoOutput.connection(with: .video) { CameraController.portrait(c) }
        session.commitConfiguration()
        configurePhotoDimensions()
        configured = true
    }

    private func configurePhotoDimensions() {
        if #available(iOS 16.0, *) {
            guard let input = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput })
                    .first(where: { $0.device.hasMediaType(.video) }) else { return }
            let dims = input.device.activeFormat.supportedMaxPhotoDimensions
            if let best = dims.max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }) {
                photoOutput.maxPhotoDimensions = best
            }
        }
    }

    static func portrait(_ c: AVCaptureConnection) {
        if #available(iOS 17.0, *) {
            if c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        } else {
            if c.isVideoOrientationSupported { c.videoOrientation = .portrait }
        }
    }

    // MARK: video
    func record(maxSeconds: Int, completion: @escaping (URL?, Double) -> Void) {
        queue.async {
            guard !self.movieOutput.isRecording else { return }
            self.movieCompletion = completion
            if let c = self.movieOutput.connection(with: .video) { CameraController.portrait(c) }
            self.movieOutput.maxRecordedDuration = CMTime(seconds: Double(maxSeconds), preferredTimescale: 600)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
    }

    func stopRecording() {
        queue.async {
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
        }
    }

    /// Drop whatever is being recorded (guest hit cancel).
    func discardRecording() {
        queue.async {
            self.movieCompletion = nil
            if self.movieOutput.isRecording { self.movieOutput.stopRecording() }
        }
    }

    private func finishMovie(_ url: URL?, _ seconds: Double) {
        let cb = movieCompletion
        movieCompletion = nil
        DispatchQueue.main.async { cb?(url, seconds) }
    }

    /// .mov -> .mp4 without re-encoding so it plays on every phone browser.
    private func exportMP4(_ src: URL, completion: @escaping (URL) -> Void) {
        let asset = AVURLAsset(url: src)
        let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        guard let ex = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
            completion(src); return
        }
        ex.outputURL = out
        ex.outputFileType = .mp4
        ex.shouldOptimizeForNetworkUse = true
        ex.exportAsynchronously {
            if ex.status == .completed {
                try? FileManager.default.removeItem(at: src)
                completion(out)
            } else {
                completion(src)
            }
        }
    }

    // MARK: photo
    func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        queue.async {
            self.photoCompletion = completion
            if let c = self.photoOutput.connection(with: .video) { CameraController.portrait(c) }
            let settings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.jpeg) {
                settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            } else {
                settings = AVCapturePhotoSettings()
            }
            if #available(iOS 16.0, *) {
                settings.maxPhotoDimensions = self.photoOutput.maxPhotoDimensions
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraController: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL,
                    from connections: [AVCaptureConnection], error: Error?) {
        var ok = true
        if let err = error as NSError? {
            ok = (err.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool) ?? false
        }
        let seconds = output.recordedDuration.seconds
        guard movieCompletion != nil else {
            try? FileManager.default.removeItem(at: outputFileURL)
            return
        }
        guard ok, seconds.isFinite, seconds > 0.5 else {
            try? FileManager.default.removeItem(at: outputFileURL)
            finishMovie(nil, 0)
            return
        }
        exportMP4(outputFileURL) { url in
            self.queue.async { self.finishMovie(url, seconds) }
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let image = photo.fileDataRepresentation().flatMap { UIImage(data: $0) }
        let cb = photoCompletion
        photoCompletion = nil
        DispatchQueue.main.async { cb?(image) }
    }
}

// MARK: live preview
final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let c = previewLayer.connection { CameraController.portrait(c) }
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> PreviewView {
        let v = PreviewView()
        v.backgroundColor = .black
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }
    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.setNeedsLayout()
    }
}

import SwiftUI

@main
struct JJVideoBoothApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}

enum Theme {
    static let gold = Color(red: 0.79, green: 0.66, blue: 0.43)
    static let cream = Color(red: 0.95, green: 0.91, blue: 0.85)
    static let dark = Color(red: 0.055, green: 0.04, blue: 0.03)
    static func serif(_ size: CGFloat) -> Font { .custom("Georgia", size: size) }
    static func serifBold(_ size: CGFloat) -> Font { .custom("Georgia-Bold", size: size) }
}

struct BigButton: View {
    let title: String
    var filled = true
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .padding(.horizontal, 54).padding(.vertical, 24)
                .frame(minWidth: 380)
                .foregroundColor(filled ? Theme.dark : Theme.cream)
                .background(filled ? AnyShapeStyle(Theme.gold) : AnyShapeStyle(Color.white.opacity(0.12)))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Theme.gold, lineWidth: filled ? 0 : 2))
        }
        .buttonStyle(.plain)
    }
}

struct ContentView: View {
    @StateObject var model = BoothModel()
    @ObservedObject var settings = BoothSettings.shared
    @State var showSettings = false
    @State var showPin = false
    @State var pin = ""
    @State var showGallery = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: model.camera.session).ignoresSafeArea()

            Group {
                switch model.step {
                case .attract: AttractView(model: model, showGallery: $showGallery)
                case .videoIntro: VideoIntroView(model: model)
                case .videoCountdown, .photoCountdown: CountdownView(model: model)
                case .recording: RecordingView(model: model)
                case .savingVideo: BusyView(text: "Saving your message…")
                case .photoIntro: PhotoIntroView(model: model)
                case .processing: BusyView(text: "Making your print…")
                case .share: ShareView(model: model)
                }
            }
            .transition(.opacity)

            if model.flash { Color.white.ignoresSafeArea() }

            if model.camera.permissionDenied {
                Text("Camera access is off. Turn it on in Settings › J&J Video Booth.")
                    .font(.title2).padding(30).background(.black.opacity(0.8)).cornerRadius(16)
            }

            // Hidden operator corner: hold the top-right corner for 2 seconds.
            VStack {
                HStack {
                    Spacer()
                    Color.clear.frame(width: 110, height: 110).contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 2) { pin = ""; showPin = true }
                }
                Spacer()
            }
            .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.25), value: model.step)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            model.camera.start(hd1080: settings.hd1080)
        }
        .onChange(of: settings.hd1080) { v in model.camera.applyQuality(hd1080: v) }
        .alert("Operator PIN", isPresented: $showPin) {
            SecureField("PIN", text: $pin).keyboardType(.numberPad)
            Button("Open") { if pin == settings.settingsPin { model.cancel(); showSettings = true } }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showSettings) { SettingsView(model: model) }
        .fullScreenCover(isPresented: $showGallery) { GalleryView(model: model) }
    }
}

struct Backdrop: View {
    var opacity: Double = 0.55
    var body: some View {
        LinearGradient(colors: [Theme.dark.opacity(opacity + 0.2), Theme.dark.opacity(opacity), Theme.dark.opacity(opacity + 0.25)],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

struct CancelButton: View {
    let action: () -> Void
    var body: some View {
        VStack {
            HStack {
                Button(action: action) {
                    Image(systemName: "xmark").font(.system(size: 26, weight: .bold))
                        .padding(22).background(.black.opacity(0.5)).clipShape(Circle())
                }
                .padding(30)
                Spacer()
            }
            Spacer()
        }
    }
}

struct AttractView: View {
    @ObservedObject var model: BoothModel
    @ObservedObject var settings = BoothSettings.shared
    @Binding var showGallery: Bool
    @State var pulse = false

    var body: some View {
        ZStack {
            Backdrop(opacity: 0.6)
            VStack(spacing: 28) {
                Spacer()
                if !settings.eventTitle.isEmpty {
                    Text(settings.eventTitle.uppercased())
                        .font(.system(size: 22, weight: .semibold)).kerning(6).foregroundColor(Theme.gold)
                }
                Text("Leave \(settings.honoreeOrGuest)\na video message")
                    .font(Theme.serifBold(72)).multilineTextAlignment(.center).foregroundColor(Theme.cream)
                Text("Then strike a pose — your photo prints right here 📸")
                    .font(Theme.serif(30)).foregroundColor(Theme.cream.opacity(0.85)).multilineTextAlignment(.center)
                    .padding(.horizontal, 60)
                BigButton(title: "Tap to Start") { model.start() }
                    .scaleEffect(pulse ? 1.05 : 0.97)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                    .padding(.top, 20)
                if !model.message.isEmpty {
                    Text(model.message).font(.title3).foregroundColor(.orange)
                }
                if !settings.hasEvent {
                    Text("Operator: hold the top-right corner to set up an event")
                        .font(.headline).foregroundColor(.orange)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    Button { showGallery = true } label: {
                        Label("Tonight's Gallery", systemImage: "square.grid.2x2.fill")
                            .font(.title2.bold()).padding(.horizontal, 28).padding(.vertical, 18)
                            .background(.black.opacity(0.5)).clipShape(Capsule())
                            .foregroundColor(Theme.cream)
                    }
                    Spacer()
                    if settings.hasEvent, let qr = QR.image(settings.nightGalleryLink, size: 300) {
                        VStack(spacing: 8) {
                            Image(uiImage: qr).interpolation(.none).resizable().frame(width: 130, height: 130)
                                .padding(8).background(Color.white).cornerRadius(10)
                            Text("Gallery on your phone").font(.caption.bold()).foregroundColor(Theme.cream)
                        }
                    }
                }
                .padding(40)
            }
        }
        .contentShape(Rectangle())
        .onAppear { pulse = true }
    }
}

struct VideoIntroView: View {
    @ObservedObject var model: BoothModel
    var body: some View {
        ZStack {
            Backdrop(opacity: 0.35)
            VStack(spacing: 26) {
                Spacer()
                Image(systemName: "video.fill").font(.system(size: 64)).foregroundColor(Theme.gold)
                Text("Say something to\n\(model.settings.honoreeOrGuest)!")
                    .font(Theme.serifBold(64)).multilineTextAlignment(.center)
                Text("You get up to \(model.settings.videoSeconds) seconds. Look at the camera and talk —\nwe'll save it just for them.")
                    .font(Theme.serif(28)).multilineTextAlignment(.center).opacity(0.9)
                BigButton(title: "Start Recording") { model.beginVideo() }.padding(.top, 16)
                BigButton(title: "Skip — just photos", filled: false) { model.skipVideo() }
                Spacer()
            }
            .foregroundColor(Theme.cream).padding(40)
            CancelButton { model.cancel() }
        }
    }
}

struct CountdownView: View {
    @ObservedObject var model: BoothModel
    var body: some View {
        ZStack {
            VStack {
                Text(model.step == .videoCountdown ? "Recording in…" :
                        "Photo \(model.shotIndex + 1) of \(max(1, model.settings.shots))")
                    .font(Theme.serifBold(44)).padding(.horizontal, 30).padding(.vertical, 14)
                    .background(.black.opacity(0.45)).clipShape(Capsule())
                    .padding(.top, 70)
                Spacer()
            }
            Text("\(model.countdown)")
                .font(.system(size: 320, weight: .heavy, design: .rounded))
                .foregroundColor(.white).shadow(color: .black.opacity(0.6), radius: 20)
                .id(model.countdown)
                .transition(.scale.combined(with: .opacity))
            CancelButton { model.cancel() }
        }
        .foregroundColor(Theme.cream)
        .animation(.spring(response: 0.35), value: model.countdown)
    }
}

struct RecordingView: View {
    @ObservedObject var model: BoothModel
    var body: some View {
        let total = Double(model.settings.videoSeconds)
        let left = max(0, Int(ceil(total - model.elapsed)))
        ZStack {
            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    Circle().fill(Color.red).frame(width: 26, height: 26)
                    Text("REC  \(left)s left").font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                }
                .padding(.horizontal, 30).padding(.vertical, 16)
                .background(.black.opacity(0.55)).clipShape(Capsule())
                ProgressView(value: model.elapsed, total: total).tint(.red).frame(width: 500)
                Spacer()
                BigButton(title: "I'm Done") { model.stopRecording() }.padding(.bottom, 80)
            }
            .padding(.top, 60)
        }
        .foregroundColor(.white)
    }
}

struct PhotoIntroView: View {
    @ObservedObject var model: BoothModel
    var body: some View {
        ZStack {
            Backdrop(opacity: 0.3)
            VStack(spacing: 26) {
                Spacer()
                Image(systemName: "camera.fill").font(.system(size: 64)).foregroundColor(Theme.gold)
                Text("Now strike a pose!").font(Theme.serifBold(70))
                let n = max(1, model.settings.shots)
                Text(n == 1 ? "We'll take one photo and print it for you." : "We'll take \(n) photos and print them for you.")
                    .font(Theme.serif(30)).opacity(0.9)
                if !model.message.isEmpty { Text(model.message).font(.title3).foregroundColor(.orange) }
                BigButton(title: "I'm Ready!") { model.beginPhotos() }.padding(.top, 16)
                Spacer()
            }
            .foregroundColor(Theme.cream).padding(40)
            CancelButton { model.cancel() }
        }
    }
}

struct BusyView: View {
    let text: String
    var body: some View {
        ZStack {
            Backdrop(opacity: 0.7)
            VStack(spacing: 24) {
                ProgressView().scaleEffect(2.2).tint(Theme.gold)
                Text(text).font(Theme.serifBold(46)).foregroundColor(Theme.cream)
            }
        }
    }
}

import SwiftUI

/// After the photos: print preview, QR to grab everything on their phone, and email.
struct ShareView: View {
    @ObservedObject var model: BoothModel
    var body: some View {
        ZStack {
            Theme.dark.opacity(0.92).ignoresSafeArea()
            ScrollView {
                VStack(spacing: 26) {
                    Text("You're all set! 🎉").font(Theme.serifBold(58)).foregroundColor(Theme.cream).padding(.top, 50)
                    if let img = model.printImage {
                        Image(uiImage: img).resizable().scaledToFit()
                            .frame(height: 520).cornerRadius(8).shadow(radius: 14)
                    }
                    if !model.printStatus.isEmpty {
                        Text(model.printStatus).font(.title2.bold())
                            .foregroundColor(model.printStatus.hasPrefix("Print problem") ? .orange : Theme.gold)
                            .multilineTextAlignment(.center)
                    }
                    if let s = model.current {
                        SendPanel(session: s, onTouch: { model.touch() }, onEmail: { model.sendEmail($0) })
                    }
                    BigButton(title: "Done") { model.done() }.padding(.bottom, 50)
                }
                .padding(.horizontal, 40)
                .frame(maxWidth: .infinity)
            }
            .simultaneousGesture(TapGesture().onEnded { model.touch() })
        }
    }
}

/// QR code + email box. Used on the share screen and in the gallery.
struct SendPanel: View {
    let session: BoothSession
    var onTouch: () -> Void = {}
    let onEmail: (String) -> Void
    @ObservedObject var settings = BoothSettings.shared
    @ObservedObject var store = SessionStore.shared
    @State var email = ""
    @State var sent: [String] = []

    var body: some View {
        let live = store.session(session.code) ?? session
        HStack(alignment: .top, spacing: 36) {
            VStack(spacing: 12) {
                if let qr = QR.image(settings.guestLink(session.code), size: 500) {
                    Image(uiImage: qr).interpolation(.none).resizable().frame(width: 250, height: 250)
                        .padding(12).background(Color.white).cornerRadius(14)
                }
                Text(live.hasVideo ? "Scan to save your photo\n& video on your phone" : "Scan to save your\nphoto on your phone")
                    .font(.headline).multilineTextAlignment(.center).foregroundColor(Theme.cream)
                Text(live.uploaded ? "Ready ✓" : "Uploading… link works in a moment")
                    .font(.subheadline).foregroundColor(live.uploaded ? .green : Theme.gold)
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Or email it to yourself").font(.title2.bold()).foregroundColor(Theme.cream)
                TextField("you@email.com", text: $email, onEditingChanged: { _ in onTouch() })
                    .keyboardType(.emailAddress).textContentType(.emailAddress)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.title2).padding(18).background(Color.white).foregroundColor(.black).cornerRadius(12)
                    .frame(width: 400)
                    .onSubmit(submit)
                Button(action: submit) {
                    Text("Send").font(.title2.bold()).frame(width: 400).padding(.vertical, 16)
                        .background(valid ? Theme.gold : Color.gray.opacity(0.5)).foregroundColor(Theme.dark).cornerRadius(12)
                }
                .disabled(!valid)
                ForEach(sent, id: \.self) { e in
                    let done = live.sentEmails.contains(e)
                    Label(done ? "Sent to \(e)" : "Sending to \(e)…", systemImage: done ? "checkmark.circle.fill" : "paperplane")
                        .foregroundColor(done ? .green : Theme.gold)
                }
            }
        }
        .padding(28).background(Color.white.opacity(0.07)).cornerRadius(20)
        .onAppear { sent = session.pendingEmails + session.sentEmails }
    }

    private var valid: Bool {
        let e = email.trimmingCharacters(in: .whitespaces)
        return e.contains("@") && e.contains(".") && e.count >= 6
    }

    private func submit() {
        guard valid else { return }
        let e = email.trimmingCharacters(in: .whitespaces)
        onEmail(e)
        if !sent.contains(e) { sent.append(e) }
        email = ""
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Tonight's gallery: every print from the current event, newest first.
struct GalleryView: View {
    @ObservedObject var model: BoothModel
    @ObservedObject var store = SessionStore.shared
    @ObservedObject var settings = BoothSettings.shared
    @Environment(\.dismiss) var dismiss
    @State var selected: BoothSession?

    var body: some View {
        let items = store.sessions(forEvent: settings.eventSlug)
        NavigationStack {
            ScrollView {
                if items.isEmpty {
                    Text("No photos yet tonight — be the first! 📸")
                        .font(Theme.serif(32)).foregroundColor(Theme.cream).padding(.top, 120)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 18)], spacing: 18) {
                    ForEach(items) { s in
                        Thumb(code: s.code)
                            .onTapGesture { selected = s }
                    }
                }
                .padding(24)
            }
            .background(Theme.dark.ignoresSafeArea())
            .navigationTitle(settings.eventTitle.isEmpty ? "Tonight's Gallery" : settings.eventTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }.font(.title3.bold())
                }
            }
        }
        .sheet(item: $selected) { s in GalleryDetail(model: model, session: s) }
    }
}

struct Thumb: View {
    let code: String
    @State var img: UIImage?
    var body: some View {
        ZStack {
            Color.white.opacity(0.08)
            if let img = img { Image(uiImage: img).resizable().scaledToFit() }
            else { ProgressView() }
        }
        .aspectRatio(2.0 / 3.0, contentMode: .fit)
        .cornerRadius(8)
        .onAppear {
            guard img == nil else { return }
            let url = SessionStore.shared.photoURL(code)
            DispatchQueue.global(qos: .userInitiated).async {
                let full = UIImage(contentsOfFile: url.path)
                let thumb = full?.preparingThumbnail(of: CGSize(width: 400, height: 600)) ?? full
                DispatchQueue.main.async { img = thumb }
            }
        }
    }
}

struct GalleryDetail: View {
    @ObservedObject var model: BoothModel
    let session: BoothSession
    @ObservedObject var settings = BoothSettings.shared
    @Environment(\.dismiss) var dismiss
    @State var status = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let img = SessionStore.shared.photo(session.code) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 640).cornerRadius(8)
                        if settings.allowGuestReprint {
                            Button {
                                status = "Printing…"
                                PrinterService.shared.print(img, copies: 1) { ok, msg in status = ok ? "Printed ✓" : msg }
                            } label: {
                                Label("Print another copy", systemImage: "printer.fill").font(.title3.bold())
                            }
                            if !status.isEmpty { Text(status).foregroundColor(Theme.gold) }
                        }
                    }
                    SendPanel(session: session, onEmail: { SessionStore.shared.queueEmail($0, for: session.code) })
                }
                .padding(30)
            }
            .background(Theme.dark.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Close") { dismiss() }.font(.title3.bold()) }
            }
        }
    }
}

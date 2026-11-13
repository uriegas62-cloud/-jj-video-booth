import SwiftUI

/// Operator screen (hold top-right corner 2s + PIN).
struct SettingsView: View {
    @ObservedObject var model: BoothModel
    @ObservedObject var settings = BoothSettings.shared
    @ObservedObject var store = SessionStore.shared
    @ObservedObject var printer = PrinterService.shared
    @Environment(\.dismiss) var dismiss

    @State var events: [EventRow] = []
    @State var eventsError = ""
    @State var loading = false
    @State var newTitle = ""
    @State var newHonoree = ""
    @State var newDate = Date()
    @State var newPin = ""
    @State var printerStatus = ""
    @State var showLinks = false

    var body: some View {
        NavigationStack {
            Form {
                eventSection
                newEventSection
                if settings.hasEvent { linksSection }
                printerSection
                boothSection
                uploadsSection
            }
            .navigationTitle("Booth Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.bold() }
            }
        }
    }

    // MARK: event
    var eventSection: some View {
        Section {
            if settings.hasEvent {
                LabeledContent("Current event", value: settings.eventTitle)
                LabeledContent("For", value: settings.honoree)
                LabeledContent("Event code", value: settings.eventSlug)
            } else {
                Text("No event selected — load or create one below.").foregroundColor(.orange)
            }
            SecureField("Admin key", text: $settings.adminKey)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button(loading ? "Loading…" : "Load my events") { loadEvents() }
                .disabled(settings.adminKey.isEmpty || loading)
            if !eventsError.isEmpty { Text(eventsError).foregroundColor(.red) }
            ForEach(events) { e in
                Button { select(e) } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.title).bold()
                            Text("\(e.honoree) · \(e.event_date ?? "") · \(e.sessions ?? 0) guests").font(.caption).foregroundColor(.secondary)
                        }
                        Spacer()
                        if e.slug == settings.eventSlug { Image(systemName: "checkmark.circle.fill").foregroundColor(.green) }
                    }
                }
            }
        } header: { Text("Event") }
    }

    var newEventSection: some View {
        Section {
            TextField("Event name (prints on the photo) — e.g. Maria's 50th", text: $newTitle)
            TextField("Who it's for — e.g. Maria", text: $newHonoree)
            DatePicker("Date", selection: $newDate, displayedComponents: .date)
            TextField("Host PIN for the video gallery (4+ characters)", text: $newPin)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Create event") { createEvent() }
                .disabled(settings.adminKey.isEmpty || newTitle.isEmpty || newHonoree.isEmpty || newPin.count < 4)
        } header: { Text("New event") }
    }

    // MARK: links
    var linksSection: some View {
        Section {
            linkRow("Tonight's gallery (guests)", settings.nightGalleryLink)
            linkRow("Host video gallery (needs host PIN)", settings.hostGalleryLink)
            Button("Print a gallery QR table sign") {
                let sign = PrintComposer.gallerySign(title: settings.eventTitle, link: settings.nightGalleryLink)
                printerStatus = "Printing sign…"
                PrinterService.shared.print(sign, copies: 1) { ok, msg in printerStatus = ok ? "Sign printed ✓" : msg }
            }
        } header: { Text("Links") } footer: {
            Text("Send the host link + PIN to the person the party is for. It has every video message and photo, with Download All.")
        }
    }

    func linkRow(_ label: String, _ link: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(label).bold()
                Text(link).font(.caption).foregroundColor(.secondary).textSelection(.enabled)
            }
            Spacer()
            Button { UIPasteboard.general.string = link } label: { Image(systemName: "doc.on.doc") }
                .buttonStyle(.borderless)
        }
    }

    // MARK: printer
    var printerSection: some View {
        Section {
            LabeledContent("Printer", value: settings.printerName.isEmpty ? "None chosen" : settings.printerName)
            Button("Choose printer") {
                PrinterService.shared.pick(current: settings.printerURL) { url, name in
                    if let url = url {
                        settings.printerURL = url
                        settings.printerName = name ?? "Printer"
                        printerStatus = "Saved ✓"
                    }
                }
            }
            Button("Check printer is reachable") {
                printerStatus = "Checking…"
                PrinterService.shared.contact(settings.printerURL) { ok in
                    printerStatus = ok ? "Printer is online ✓" : "Can't reach the printer — same Wi-Fi? Powered on?"
                }
            }
            .disabled(settings.printerURL.isEmpty)
            Button("Test print") {
                let test = PrintComposer.compose(shots: [testImage()], title: settings.eventTitle.isEmpty ? "Test Print" : settings.eventTitle,
                                                 subtitle: settings.eventDateText)
                printerStatus = "Printing test…"
                PrinterService.shared.print(test, copies: 1) { ok, msg in printerStatus = ok ? "Test printed ✓" : msg }
            }
            .disabled(settings.printerURL.isEmpty)
            Toggle("Print automatically", isOn: $settings.autoPrint)
            Stepper("Copies per guest: \(settings.copies)", value: $settings.copies, in: 1...4)
            Toggle("Let guests reprint from the gallery", isOn: $settings.allowGuestReprint)
            if !printerStatus.isEmpty { Text(printerStatus).foregroundColor(.blue) }
            if !printer.lastPapers.isEmpty {
                Text("Last job — papers offered: \(printer.lastPapers)\nChosen: \(printer.lastChosen)")
                    .font(.caption).foregroundColor(.secondary)
            }
        } header: { Text("Printer (Epson)") } footer: {
            Text("Load 4x6 photo paper in the Epson's photo tray and set the paper size to 4x6 on the printer's screen. Pick the printer once here — after that every print goes out silently.")
        }
    }

    // MARK: booth
    var boothSection: some View {
        Section {
            Picker("Video message length", selection: $settings.videoSeconds) {
                Text("15 sec").tag(15)
                Text("30 sec").tag(30)
                Text("45 sec").tag(45)
                Text("60 sec").tag(60)
            }
            Picker("Photos per print", selection: $settings.shots) {
                Text("1 big photo").tag(1)
                Text("3 photos").tag(3)
                Text("4 photos (grid)").tag(4)
            }
            Picker("Countdown", selection: $settings.countdownSeconds) {
                Text("3 sec").tag(3)
                Text("5 sec").tag(5)
            }
            Toggle("1080p video (bigger uploads)", isOn: $settings.hd1080)
            TextField("Date line on the print", text: $settings.eventDateText)
            TextField("Operator PIN", text: $settings.settingsPin).keyboardType(.numberPad)
            TextField("Gallery website", text: $settings.galleryBase)
                .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
        } header: { Text("Booth") }
    }

    // MARK: uploads
    var uploadsSection: some View {
        Section {
            LabeledContent("Guests saved on this iPad", value: "\(store.sessions.count)")
            LabeledContent("Waiting to upload / email", value: "\(store.pendingCount)")
            if !store.lastUploadError.isEmpty { Text(store.lastUploadError).foregroundColor(.orange) }
            Button("Retry uploads now") { store.processQueue() }
        } header: { Text("Uploads") } footer: {
            Text("Everything is saved on the iPad first, so a Wi-Fi drop never loses a video. Leave the app open after the party until this hits 0.")
        }
    }

    // MARK: actions
    func loadEvents() {
        loading = true; eventsError = ""
        API.rpc("vb_list_events", ["p_admin_key": settings.adminKey], as: [EventRow].self) { r in
            loading = false
            switch r {
            case .success(let list): events = list; if list.isEmpty { eventsError = "No events yet — create one below." }
            case .failure(let e): eventsError = e.localizedDescription
            }
        }
    }

    func createEvent() {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let params: [String: Any] = ["p_admin_key": settings.adminKey, "p_title": newTitle, "p_honoree": newHonoree,
                                     "p_event_date": f.string(from: newDate), "p_host_pin": newPin]
        API.rpc("vb_create_event", params, as: [EventRow].self) { r in
            switch r {
            case .success(let list):
                if let e = list.first {
                    let pretty = DateFormatter(); pretty.dateStyle = .long
                    select(e, dateText: pretty.string(from: newDate))
                    newTitle = ""; newHonoree = ""; newPin = ""
                    loadEvents()
                }
            case .failure(let e): eventsError = e.localizedDescription
            }
        }
    }

    func select(_ e: EventRow, dateText: String? = nil) {
        settings.eventSlug = e.slug
        settings.uploadKey = e.upload_key
        settings.eventTitle = e.title
        settings.honoree = e.honoree
        if let t = dateText {
            settings.eventDateText = t
        } else if let d = e.event_date {
            let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
            let out = DateFormatter(); out.dateStyle = .long
            settings.eventDateText = inF.date(from: d).map { out.string(from: $0) } ?? d
        }
    }

    func testImage() -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.85, green: 0.78, blue: 0.66, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let p = NSMutableParagraphStyle(); p.alignment = .center
            NSAttributedString(string: "TEST PRINT\n4 x 6", attributes: [.font: UIFont.boldSystemFont(ofSize: 110), .foregroundColor: UIColor.darkGray, .paragraphStyle: p])
                .draw(with: CGRect(x: 0, y: 420, width: size.width, height: 400), options: .usesLineFragmentOrigin, context: nil)
        }
    }
}

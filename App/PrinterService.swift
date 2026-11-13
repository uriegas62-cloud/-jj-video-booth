import UIKit

/// Silent AirPrint to the saved Epson. Pick the printer once in settings; after that every print
/// goes straight to it as a 4x6 photo job with no print sheet.
final class PrinterService: NSObject, ObservableObject {
    static let shared = PrinterService()
    @Published var lastPapers = ""
    @Published var lastChosen = ""
    private let paperDelegate = PaperDelegate()
    private var printing = false
    private var queue: [(UIImage, Int, (Bool, String) -> Void)] = []

    static func topView() -> UIView? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap { $0.windows }.first { $0.isKeyWindow } ?? scenes.first?.windows.first
        var vc = window?.rootViewController
        while let p = vc?.presentedViewController { vc = p }
        return vc?.view
    }

    func pick(current: String, completion: @escaping (String?, String?) -> Void) {
        guard let view = PrinterService.topView() else { completion(nil, nil); return }
        let initial = URL(string: current).map { UIPrinter(url: $0) }
        let picker = UIPrinterPickerController(initiallySelectedPrinter: initial)
        let anchor = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        _ = picker.present(from: anchor, in: view, animated: true) { controller, selected, _ in
            if selected, let p = controller.selectedPrinter {
                completion(p.url.absoluteString, p.displayName)
            } else {
                completion(nil, nil)
            }
        }
    }

    func contact(_ urlString: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: urlString) else { completion(false); return }
        UIPrinter(url: url).contactPrinter { ok in DispatchQueue.main.async { completion(ok) } }
    }

    /// Queues a print. Jobs go one at a time so back-to-back guests don't collide.
    func print(_ image: UIImage, copies: Int, completion: @escaping (Bool, String) -> Void) {
        queue.append((image, max(1, min(5, copies)), completion))
        runNext()
    }

    private func runNext() {
        guard !printing, !queue.isEmpty else { return }
        let (image, copies, completion) = queue.removeFirst()
        guard let url = URL(string: BoothSettings.shared.printerURL), !BoothSettings.shared.printerURL.isEmpty else {
            completion(false, "No printer chosen — open settings and pick the Epson")
            runNext()
            return
        }
        printing = true
        let pdf = PrinterService.make4x6Page(image)
        printCopies(pdf, UIPrinter(url: url), remaining: copies) { ok, msg in
            self.printing = false
            completion(ok, msg)
            self.runNext()
        }
    }

    /// Exactly 4 x 6 in (288 x 432 pt), edge to edge, so the job asks for 4x6 borderless.
    static func make4x6Page(_ image: UIImage) -> Data {
        let page = CGRect(x: 0, y: 0, width: 288, height: 432)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { ctx in
            ctx.beginPage()
            UIColor.white.setFill()
            ctx.fill(page)
            let iw = image.size.width, ih = image.size.height
            guard iw > 0, ih > 0 else { return }
            let scale = max(page.width / iw, page.height / ih)
            let w = iw * scale, h = ih * scale
            image.draw(in: CGRect(x: (page.width - w) / 2, y: (page.height - h) / 2, width: w, height: h))
        }
    }

    private func printCopies(_ pdf: Data, _ printer: UIPrinter, remaining: Int, done: @escaping (Bool, String) -> Void) {
        if remaining <= 0 { done(true, "Printed"); return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo
        info.jobName = "J&J Video Booth"
        info.orientation = .portrait
        controller.printInfo = info
        controller.showsNumberOfCopies = false
        controller.showsPaperSelectionForLoadedPapers = false
        controller.delegate = paperDelegate
        controller.printingItem = pdf
        let started = controller.print(to: printer) { _, completed, error in
            self.lastPapers = self.paperDelegate.lastPapers
            self.lastChosen = self.paperDelegate.lastChosen
            if let error = error { done(false, error.localizedDescription); return }
            if !completed { done(false, "Print didn't complete — check the printer is on and has paper"); return }
            self.printCopies(pdf, printer, remaining: remaining - 1, done: done)
        }
        if !started { done(false, "Couldn't reach the printer") }
    }
}

/// Picks the loaded paper closest to 4x6 so the print fills the photo paper.
final class PaperDelegate: NSObject, UIPrintInteractionControllerDelegate {
    var lastPapers = ""
    var lastChosen = ""

    private func describe(_ p: UIPrintPaper) -> String {
        String(format: "%.1fx%.1f", p.paperSize.width / 72.0, p.paperSize.height / 72.0)
    }

    func printInteractionController(_ printInteractionController: UIPrintInteractionController,
                                    choosePaper paperList: [UIPrintPaper]) -> UIPrintPaper {
        lastPapers = paperList.map { describe($0) }.joined(separator: ", ")
        let exact = paperList.first { p in
            let w = p.paperSize.width, h = p.paperSize.height
            return (abs(w - 288) < 6 && abs(h - 432) < 6) || (abs(w - 432) < 6 && abs(h - 288) < 6)
        }
        let chosen = exact ?? UIPrintPaper.bestPaper(forPageSize: CGSize(width: 288, height: 432), withPapersFrom: paperList)
        lastChosen = describe(chosen) + (exact != nil ? " (exact)" : " (closest)")
        return chosen
    }
}

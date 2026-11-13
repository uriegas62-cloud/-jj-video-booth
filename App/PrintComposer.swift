import UIKit
import CoreImage.CIFilterBuiltins

/// Builds the 4x6 print (1200 x 1800 px = 300 dpi).
enum PrintComposer {
    static let size = CGSize(width: 1200, height: 1800)
    static let gold = UIColor(red: 0.69, green: 0.55, blue: 0.30, alpha: 1)
    static let ink = UIColor(red: 0.12, green: 0.09, blue: 0.07, alpha: 1)

    static func compose(shots: [UIImage], title: String, subtitle: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let m: CGFloat = 60, gap: CGFloat = 30
            let areaW = size.width - 2 * m          // 1080
            let areaH: CGFloat = 1410                // photos area, footer below
            var rects: [CGRect] = []
            switch shots.count {
            case 0: break
            case 1:
                rects = [CGRect(x: m, y: m, width: areaW, height: areaH)]
            case 2:
                let h = (areaH - gap) / 2
                rects = [CGRect(x: m, y: m, width: areaW, height: h),
                         CGRect(x: m, y: m + h + gap, width: areaW, height: h)]
            case 3:
                let smallW = (areaW - gap) / 2, smallH: CGFloat = 700
                let bigH = areaH - gap - smallH
                rects = [CGRect(x: m, y: m, width: areaW, height: bigH),
                         CGRect(x: m, y: m + bigH + gap, width: smallW, height: smallH),
                         CGRect(x: m + smallW + gap, y: m + bigH + gap, width: smallW, height: smallH)]
            default:
                let w = (areaW - gap) / 2, h = (areaH - gap) / 2
                rects = [CGRect(x: m, y: m, width: w, height: h),
                         CGRect(x: m + w + gap, y: m, width: w, height: h),
                         CGRect(x: m, y: m + h + gap, width: w, height: h),
                         CGRect(x: m + w + gap, y: m + h + gap, width: w, height: h)]
            }
            for (img, r) in zip(shots, rects) { drawFill(img, in: r, ctx: ctx.cgContext) }

            // footer
            let footerTop = m + areaH
            gold.setFill()
            ctx.fill(CGRect(x: size.width / 2 - 140, y: footerTop + 55, width: 280, height: 4))
            let p = NSMutableParagraphStyle(); p.alignment = .center
            let titleFont = UIFont(name: "Georgia-Bold", size: 88) ?? .boldSystemFont(ofSize: 88)
            let subFont = UIFont(name: "Georgia-Italic", size: 40) ?? .italicSystemFont(ofSize: 40)
            let t = NSAttributedString(string: title, attributes: [.font: titleFont, .foregroundColor: ink, .paragraphStyle: p])
            t.draw(with: CGRect(x: m, y: footerTop + 85, width: areaW, height: 110),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            let s = NSAttributedString(string: subtitle, attributes: [.font: subFont, .foregroundColor: gold, .paragraphStyle: p])
            s.draw(with: CGRect(x: m, y: footerTop + 200, width: areaW, height: 60),
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], context: nil)
            let brandFont = UIFont(name: "AvenirNext-DemiBold", size: 26) ?? .systemFont(ofSize: 26, weight: .semibold)
            let b = NSAttributedString(string: "J&J WORKSHOP PHOTO BOOTH", attributes: [.font: brandFont, .foregroundColor: UIColor.gray, .kern: 4, .paragraphStyle: p])
            b.draw(with: CGRect(x: m, y: size.height - 70, width: areaW, height: 40), options: .usesLineFragmentOrigin, context: nil)
        }
    }

    /// Aspect-fill crop, biased a little toward the top so heads don't get cut.
    static func drawFill(_ img: UIImage, in r: CGRect, ctx: CGContext) {
        let iw = img.size.width, ih = img.size.height
        guard iw > 0, ih > 0 else { return }
        let scale = max(r.width / iw, r.height / ih)
        let w = iw * scale, h = ih * scale
        let x = r.minX + (r.width - w) / 2
        let y = r.minY + (r.height - h) * 0.35
        ctx.saveGState()
        UIBezierPath(roundedRect: r, cornerRadius: 12).addClip()
        img.draw(in: CGRect(x: x, y: y, width: w, height: h))
        ctx.restoreGState()
    }

    /// Table sign: "Scan for tonight's gallery" with a big QR code.
    static func gallerySign(title: String, link: String) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            let p = NSMutableParagraphStyle(); p.alignment = .center
            let big = UIFont(name: "Georgia-Bold", size: 96) ?? .boldSystemFont(ofSize: 96)
            let mid = UIFont(name: "Georgia-Italic", size: 56) ?? .italicSystemFont(ofSize: 56)
            NSAttributedString(string: title, attributes: [.font: big, .foregroundColor: ink, .paragraphStyle: p])
                .draw(with: CGRect(x: 60, y: 140, width: 1080, height: 240), options: .usesLineFragmentOrigin, context: nil)
            NSAttributedString(string: "Scan for tonight's photo gallery", attributes: [.font: mid, .foregroundColor: gold, .paragraphStyle: p])
                .draw(with: CGRect(x: 60, y: 400, width: 1080, height: 80), options: .usesLineFragmentOrigin, context: nil)
            if let qr = QR.image(link, size: 800) {
                ctx.cgContext.interpolationQuality = .none
                qr.draw(in: CGRect(x: 200, y: 560, width: 800, height: 800))
            }
            let small = UIFont(name: "AvenirNext-Medium", size: 34) ?? .systemFont(ofSize: 34)
            NSAttributedString(string: "Video messages go straight to \(BoothSettings.shared.honoreeOrGuest) 💛", attributes: [.font: small, .foregroundColor: UIColor.darkGray, .paragraphStyle: p])
                .draw(with: CGRect(x: 60, y: 1440, width: 1080, height: 100), options: .usesLineFragmentOrigin, context: nil)
        }
    }
}

enum QR {
    private static let context = CIContext()
    static func image(_ text: String, size: CGFloat = 600) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage else { return nil }
        let s = size / out.extent.width
        let scaled = out.transformed(by: CGAffineTransform(scaleX: s, y: s))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

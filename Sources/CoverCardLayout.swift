import Foundation

struct CoverCardPlacement {
    let frame: CGRect
    let border: CGFloat
}

enum CoverCardLayout {
    static func placement(in size: CGSize, image: CGSize, top: CGFloat, bottom: CGFloat, horizontal: CGFloat = 40, border: CGFloat = 10) -> CoverCardPlacement {
        guard size.width > 0, size.height > 0 else { return CoverCardPlacement(frame: .zero, border: 0) }
        let top = min(max(0, top), size.height * 0.4)
        let bottom = min(max(0, bottom), size.height * 0.4)
        let horizontal = min(max(0, horizontal), size.width * 0.2)
        let available = CGRect(x: horizontal, y: top, width: size.width - horizontal * 2, height: size.height - top - bottom)
        let border = min(max(0, border), min(available.width, available.height) / 4)
        let aspect = image.width > 0 && image.height > 0 && image.width.isFinite && image.height.isFinite ? image.width / image.height : 1
        let height = min(available.height - border * 2, (available.width - border * 2) / aspect)
        let width = height * aspect
        return CoverCardPlacement(frame: CGRect(x: available.midX - width / 2 - border, y: available.midY - height / 2 - border, width: width + border * 2, height: height + border * 2), border: border)
    }
}

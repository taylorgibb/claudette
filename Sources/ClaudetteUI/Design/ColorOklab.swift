import SwiftUI

struct OklabColor {
    var L: Double
    var a: Double
    var b: Double

    init(L: Double, a: Double, b: Double) {
        self.L = L
        self.a = a
        self.b = b
    }

    init(red: Double, green: Double, blue: Double) {
        func linearize(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let r = linearize(red), g = linearize(green), bl = linearize(blue)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * bl)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * bl)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * bl)

        L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        b = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    }

    var srgb: (red: Double, green: Double, blue: Double) {
        let l3 = L + 0.3963377774 * a + 0.2158037573 * b
        let m3 = L - 0.1055613458 * a - 0.0638541728 * b
        let s3 = L - 0.0894841775 * a - 1.2914855480 * b
        let l = l3 * l3 * l3, m = m3 * m3 * m3, s = s3 * s3 * s3

        func delinearize(_ c: Double) -> Double {
            let clamped = min(max(c, 0), 1)
            return clamped <= 0.0031308 ? clamped * 12.92 : 1.055 * pow(clamped, 1 / 2.4) - 0.055
        }
        return (
            delinearize(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
            delinearize(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
            delinearize(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
        )
    }

    static func lerp(_ from: OklabColor, _ to: OklabColor, _ t: Double) -> OklabColor {
        let clamped = min(max(t, 0), 1)
        return OklabColor(
            L: from.L + (to.L - from.L) * clamped,
            a: from.a + (to.a - from.a) * clamped,
            b: from.b + (to.b - from.b) * clamped)
    }
}

extension Color {
    init(oklab: OklabColor) {
        let (r, g, b) = oklab.srgb
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1)
    }
}

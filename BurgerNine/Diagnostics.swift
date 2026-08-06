import SwiftUI
import UIKit
import OSLog

/// Layout-glitch diagnostics. The product rows and the category rail
/// occasionally jump left for a frame (transient horizontal overscroll),
/// sometimes followed by a crash. This logger instruments the three
/// suspects — the programmatic scroll anchor, the scroll-sync state
/// machine, and the per-frame geometry callbacks that feed it — so a
/// repro can be captured from Console.app (subsystem "com.burgernine.app",
/// category "menu-layout") or:
///   xcrun simctl spawn booted log stream --level debug \
///     --predicate 'subsystem == "com.burgernine.app"'
enum MenuDiag {
    static let log = Logger(subsystem: "com.burgernine.app", category: "menu-layout")

    /// True if a CGFloat would poison a CALayer frame (CoreAnimation
    /// crashes with "position contains NaN" on either of these).
    static func isBad(_ v: CGFloat) -> Bool { v.isNaN || v.isInfinite }

    // MARK: Persistent file sink
    //
    // OSLogStore on iOS can only be read with .currentProcessIdentifier scope,
    // so after a crash/freeze→restart the *previous* session's entries are
    // unreachable in-app. To survive restarts we mirror every line into a file
    // under Application Support, appended across launches and capped in size.
    // The share button zips this file, so it always includes prior sessions.

    private static let queue = DispatchQueue(label: "com.burgernine.app.diag")
    private static let maxBytes = 2 * 1024 * 1024 // ~2 MB rolling cap

    private static let fileURL: URL = {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask, appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("burgernine-diag.log")
    }()

    private static let lineFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    /// Write a session boundary so restarts are visible in the log. Call once
    /// at launch.
    static func sessionStart() {
        appendLine("──────── session start · \(UIDevice.current.systemName) \(UIDevice.current.systemVersion) · pid \(ProcessInfo.processInfo.processIdentifier) ────────")
    }

    /// Mirror a diagnostic to both the unified log (live Console) and the
    /// persistent file (survives restarts). `isError` keeps callers free of an
    /// `os` import — they don't need to know about OSLogType.
    static func record(_ message: String, isError: Bool = false) {
        let level: OSLogType = isError ? .error : .default
        log.log(level: level, "\(message, privacy: .public)")
        appendLine("[\(label(for: level))] \(message)")
    }

    private static func appendLine(_ text: String) {
        let line = "\(lineFmt.string(from: Date())) \(text)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            let fm = FileManager.default
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: fileURL)
            }
            // Cheap rotation: when oversized, keep the newer half.
            let attrs = try? fm.attributesOfItem(atPath: fileURL.path)
            let size = (attrs?[.size] as? Int) ?? 0
            if size > maxBytes, let whole = try? Data(contentsOf: fileURL) {
                try? whole.suffix(maxBytes / 2).write(to: fileURL)
            }
        }
    }

    private static func label(for level: OSLogType) -> String {
        switch level {
        case .error, .fault: "error"
        case .info: "info"
        case .debug: "debug"
        default: "notice"
        }
    }

    /// Gzip the persistent file (all sessions) for the share sheet.
    static func exportFile() -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let raw = queue.sync { (try? Data(contentsOf: fileURL)) ?? Data("(no log file yet)".utf8) }
        let dir = FileManager.default.temporaryDirectory
        if let gz = gzip(raw) {
            let url = dir.appendingPathComponent("burgernine-logs-\(stamp).txt.gz")
            try? gz.write(to: url)
            return url
        }
        let url = dir.appendingPathComponent("burgernine-logs-\(stamp).txt")
        try? raw.write(to: url)
        return url
    }

    /// Wrap a DEFLATE stream in a gzip container (RFC 1952) so the file opens
    /// with gzcat/gunzip. NSData's .zlib output is a *raw* DEFLATE block (no
    /// zlib header, no Adler32 trailer), so we use it verbatim and just add the
    /// gzip 10-byte header and the CRC32 + ISIZE footer.
    private static func gzip(_ data: Data) -> Data? {
        guard let deflate = try? (data as NSData).compressed(using: .zlib) as Data else { return nil }

        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xff]) // magic, DEFLATE, OS=unknown
        out.append(deflate)

        var crc = crc32(data).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        var size = UInt32(truncatingIfNeeded: data.count).littleEndian
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1
            }
        }
        return ~crc
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// UIKit share sheet wrapper — hands the exported log file to the OS
/// share UI (AirDrop, Messages, Save to Files, etc.).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

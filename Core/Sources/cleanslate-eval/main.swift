import Foundation
import CleanSlateCore
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

// cleanslate-eval: measures duplicate-detection quality on a labeled manifest.
//   swift run --package-path Core cleanslate-eval --manifest build/fixtures/manifest.csv [--json] [--gate]
// --gate exits non-zero if the synthetic canary gate fails (used by `make eval` and CI).

func arg(_ name: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}
let flags = Set(CommandLine.arguments)

guard let manifestPath = arg("--manifest") else {
    FileHandle.standardError.write(Data("usage: cleanslate-eval --manifest <manifest.csv> [--json] [--gate]\n".utf8)); exit(2)
}
let manifestURL = URL(fileURLWithPath: manifestPath)
guard let csv = try? String(contentsOf: manifestURL, encoding: .utf8) else {
    FileHandle.standardError.write(Data("cannot read \(manifestPath)\n".utf8)); exit(2)
}

#if canImport(ImageIO)
/// 9x8 gray rendering, via the same two-step scale the app uses (90x80, then 9x8).
func grayPixels(at url: URL) -> [UInt8]? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
    func render(_ cg: CGImage, _ w: Int, _ h: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }
    guard let mid = render(image, 90, 80), let small = render(mid, 9, 8), let data = small.dataProvider?.data else { return nil }
    return Array(UnsafeBufferPointer(start: CFDataGetBytePtr(data), count: min(72, CFDataGetLength(data))))
}
#else
func grayPixels(at url: URL) -> [UInt8]? { nil }
#endif

let root = manifestURL.deletingLastPathComponent()
let rows = Evaluation.parseManifest(csv).map { row -> EvalRow in
    let hash = grayPixels(at: root.appendingPathComponent(row.assetID)).flatMap { DifferenceHash.compute(gray9x8: $0) }
    return EvalRow(assetID: row.assetID, sceneID: row.sceneID, variant: row.variant, label: row.label, sha256: row.sha256, hash: hash)
}
if rows.isEmpty { FileHandle.standardError.write(Data("manifest has no rows\n".utf8)); exit(2) }
let hashed = rows.filter { $0.hash != nil }.count
let report = Evaluation.evaluate(rows)

if flags.contains("--json") {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    print(String(data: (try? encoder.encode(report)) ?? Data(), encoding: .utf8) ?? "{}")
} else {
    print("CleanSlate eval — \(report.scenes) scenes, \(rows.count) images (\(hashed) hashed)")
    print(String(format: "exact recall      %.3f", report.exactRecall))
    print(String(format: "exact precision   %.3f", report.exactPrecision))
    print("harmful preselected \(report.harmfulPreselected) of \(report.harmfulOpportunities) unique-content photos"
          + (report.harmfulUpperBound95.map { String(format: " (95%% upper bound %.4f)", $0) } ?? ""))
    for n in report.nearRecall { print(String(format: "near recall @ ≤%2d bits  %.3f (%d/%d)", n.maxHamming, n.recall, n.found, n.total)) }
    print("unique-content photos shown as look-alike candidates (user decides): \(report.uniqueShownAsCandidates) of \(report.uniqueTotal)")
    print("preselection gate (<0.1% upper bound): \(report.meetsPreselectionGate ? "PASSED" : "NOT passed (expected for synthetic data)")")
}

if flags.contains("--gate") {
    // Synthetic canary gate: regression detector, not evidence of real-world accuracy.
    var failures: [String] = []
    if hashed < rows.count { failures.append("only \(hashed) of \(rows.count) images could be hashed") }
    if report.exactRecall < 1 { failures.append("an exact copy was not found") }
    if report.exactPrecision < 1 { failures.append("a non-identical photo reached the Exact tier") }
    if report.harmfulPreselected > 0 { failures.append("a unique-content photo would be pre-selected") }
    if let near10 = report.nearRecall.first(where: { $0.maxHamming == 10 }), near10.recall < 1 { failures.append("re-encoded/brightened copies missed as candidates at 10 bits") }
    if failures.isEmpty { print("GATE: PASS") } else { failures.forEach { print("GATE FAIL: \($0)") }; exit(1) }
}

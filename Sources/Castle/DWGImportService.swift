import Foundation

struct DWGImportResult {
    let convertedDXFURL: URL
    let reportURL: URL
    let converterUsed: String
}

enum DWGImportError: LocalizedError {
    case converterNotFound
    case conversionFailed(String)
    case invalidConvertedDXF(String)

    var errorDescription: String? {
        switch self {
        case .converterNotFound:
            return "No DWG converter found. Run Scripts/setup-dwg2dxf.sh (or install ODA File Converter) to install dwg2dxf, or set CASTLE_DWG2DXF_PATH to a custom binary."
        case let .conversionFailed(details):
            return "DWG conversion failed. \(details)"
        case let .invalidConvertedDXF(details):
            return "DWG converted, but DXF validation failed. \(details)"
        }
    }
}

enum DWGImportService {
    static func importDWG(sourceURL: URL) throws -> DWGImportResult {
        let workspaceRoot = try importWorkspaceRoot()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let workDir = workspaceRoot.appendingPathComponent("\(baseName)-\(stamp)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        let inputDir = workDir.appendingPathComponent("input", isDirectory: true)
        let outputDir = workDir.appendingPathComponent("output", isDirectory: true)
        try FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let sourceCopy = inputDir.appendingPathComponent(sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: sourceCopy)

        let conversion = try convert(sourceDWG: sourceCopy, outputDir: outputDir)
        let convertedDXF = conversion.dxfURL
        let data = try Data(contentsOf: convertedDXF)
        let document = try DXFCodec.parse(data: data, defaultName: baseName)
        guard !document.entities.isEmpty else {
            throw DWGImportError.invalidConvertedDXF("Converted DXF has no drawable entities.")
        }

        let reportURL = workDir.appendingPathComponent("import-report.txt")
        let reportText = validationReport(
            sourceDWG: sourceURL,
            convertedDXF: convertedDXF,
            converter: conversion.converterName,
            document: document
        )
        try reportText.data(using: .utf8)?.write(to: reportURL, options: .atomic)

        return DWGImportResult(convertedDXFURL: convertedDXF, reportURL: reportURL, converterUsed: conversion.converterName)
    }

    private static func convert(sourceDWG: URL, outputDir: URL) throws -> (dxfURL: URL, converterName: String) {
        if let converted = try tryDWG2DXF(sourceDWG: sourceDWG, outputDir: outputDir) {
            return (converted, "dwg2dxf")
        }
        if let converted = try tryODAConverter(sourceDWG: sourceDWG, outputDir: outputDir) {
            return (converted, "ODA File Converter")
        }
        throw DWGImportError.converterNotFound
    }

    private static func tryDWG2DXF(sourceDWG: URL, outputDir: URL) throws -> URL? {
        let outURL = outputDir.appendingPathComponent(sourceDWG.deletingPathExtension().lastPathComponent + ".dxf")
        let variants: [[String]] = [
            ["-o", outURL.path, sourceDWG.path],
            [sourceDWG.path, "-o", outURL.path]
        ]
        let candidatePaths = try dwg2dxfCandidates()
        for candidate in candidatePaths {
            if candidate.contains("/"), !FileManager.default.isExecutableFile(atPath: candidate) {
                continue
            }
            for args in variants {
                let command = [candidate] + args
                let result = run(executable: "/usr/bin/env", arguments: command)
                if result.exitCode == 0, FileManager.default.fileExists(atPath: outURL.path) {
                    return outURL
                }
            }
        }
        return nil
    }

    private static func tryODAConverter(sourceDWG: URL, outputDir: URL) throws -> URL? {
        let odaPaths = [
            "/Applications/ODA File Converter.app/Contents/MacOS/ODAFileConverter",
            "/Applications/ODAFileConverter.app/Contents/MacOS/ODAFileConverter"
        ]
        guard let oda = odaPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            return nil
        }

        let inputDir = sourceDWG.deletingLastPathComponent()
        let attempts: [[String]] = [
            [inputDir.path, outputDir.path, "ACAD2018", "DXF", "0", "1"],
            [inputDir.path, outputDir.path, "ACAD2018", "DXF", "1", "1"],
            [inputDir.path, outputDir.path, "R2018", "DXF", "0", "1"]
        ]
        for args in attempts {
            let result = run(executable: oda, arguments: args)
            if result.exitCode == 0, let dxfURL = firstDXF(in: outputDir) {
                return dxfURL
            }
        }
        return nil
    }

    private static func firstDXF(in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for case let url as URL in enumerator {
            if url.pathExtension.caseInsensitiveCompare("dxf") == .orderedSame {
                return url
            }
        }
        return nil
    }

    private static func dwg2dxfCandidates() throws -> [String] {
        var candidates = [String]()
        let env = ProcessInfo.processInfo.environment
        if let custom = env["CASTLE_DWG2DXF_PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            candidates.append(custom)
        }
        if let resource = bundleResourceConverterPath() {
            candidates.append(resource)
        }
        let installRoot = try converterInstallRoot()
        let installed = installRoot.appendingPathComponent("dwg2dxf/dwg2dxf").path
        candidates.append(installed)
        candidates.append("dwg2dxf")

        var ordered = [String]()
        var seen = Set<String>()
        for candidate in candidates {
            if seen.insert(candidate).inserted {
                ordered.append(candidate)
            }
        }
        return ordered
    }

    private static func bundleResourceConverterPath() -> String? {
        let bases = [
            Bundle.main.resourceURL,
            Bundle.main.sharedSupportURL,
            Bundle.main.bundleURL
        ].compactMap { $0 }
        let relativePaths = [
            "Converters/dwg2dxf/dwg2dxf",
            "Contents/Resources/Converters/dwg2dxf/dwg2dxf",
            "Contents/SharedSupport/Converters/dwg2dxf/dwg2dxf"
        ]
        for base in bases {
            for relative in relativePaths {
                let candidate = base.appendingPathComponent(relative, isDirectory: false)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }
        return nil
    }

    private static func converterInstallRoot() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CASTLE_DWG_CONVERTER_ROOT"]?.trimmingCharacters(in: .whitespacesAndNewlines), !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        return base.appendingPathComponent("Castle/Converters", isDirectory: true)
    }

    private static func run(executable: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let out = Pipe()
        process.standardOutput = out
        process.standardError = out
        do {
            try process.run()
            process.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            return (process.terminationStatus, text)
        } catch {
            return (127, error.localizedDescription)
        }
    }

    private static func importWorkspaceRoot() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = base
            .appendingPathComponent("Castle", isDirectory: true)
            .appendingPathComponent("ImportedDWG", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func validationReport(
        sourceDWG: URL,
        convertedDXF: URL,
        converter: String,
        document: DXFDocument
    ) -> String {
        var lineCount = 0
        var circleCount = 0
        for entity in document.entities {
            switch entity {
            case .line: lineCount += 1
            case .circle: circleCount += 1
            }
        }

        let extents = drawingExtents(for: document)
        let extentsText: String
        if let extents {
            extentsText = String(
                format: "min(%.3f, %.3f)  max(%.3f, %.3f)",
                extents.minX,
                extents.minY,
                extents.maxX,
                extents.maxY
            )
        } else {
            extentsText = "n/a"
        }

        return """
        Castle DWG Import Report
        Date: \(ISO8601DateFormatter().string(from: Date()))
        Source DWG: \(sourceDWG.path)
        Converted DXF: \(convertedDXF.path)
        Converter: \(converter)
        Units: \(document.units.label)
        Layers: \(document.layerStyles.count)
        Entities Total: \(document.entities.count)
        LINE: \(lineCount)
        CIRCLE: \(circleCount)
        Extents: \(extentsText)
        """
    }

    private static func drawingExtents(for document: DXFDocument) -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat)? {
        guard !document.entities.isEmpty else { return nil }
        var minX = CGFloat.greatestFiniteMagnitude
        var minY = CGFloat.greatestFiniteMagnitude
        var maxX = -CGFloat.greatestFiniteMagnitude
        var maxY = -CGFloat.greatestFiniteMagnitude

        func include(_ p: DXFPoint) {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }

        for entity in document.entities {
            switch entity {
            case let .line(start, end, _, _):
                include(start)
                include(end)
            case let .circle(center, radius, _, _):
                include(DXFPoint(x: center.x - radius, y: center.y - radius))
                include(DXFPoint(x: center.x + radius, y: center.y + radius))
            }
        }

        return (minX, minY, maxX, maxY)
    }
}

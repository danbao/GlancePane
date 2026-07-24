#!/usr/bin/env swift

import Foundation

private let signature = Data([137, 80, 78, 71, 13, 10, 26, 10])
private let retainedChunks: Set<String> = [
    "IHDR", "PLTE", "IDAT", "IEND", "tRNS"
]

private func sanitizedPNG(_ data: Data) throws -> Data {
    guard data.starts(with: signature) else {
        throw NSError(domain: "SanitizePNG", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "not a PNG file"
        ])
    }

    var output = signature
    var offset = signature.count

    while offset < data.count {
        guard offset + 12 <= data.count else {
            throw NSError(domain: "SanitizePNG", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "truncated PNG chunk"
            ])
        }

        let length = data[offset..<(offset + 4)].reduce(0) { ($0 << 8) | Int($1) }
        let chunkEnd = offset + 12 + length
        guard chunkEnd <= data.count,
              let type = String(data: data[(offset + 4)..<(offset + 8)], encoding: .ascii) else {
            throw NSError(domain: "SanitizePNG", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "invalid PNG chunk"
            ])
        }

        if retainedChunks.contains(type) {
            output.append(data[offset..<chunkEnd])
        }
        offset = chunkEnd
    }

    return output
}

var arguments = Array(CommandLine.arguments.dropFirst())
let checkOnly = arguments.first == "--check"
if checkOnly {
    arguments.removeFirst()
}

guard !arguments.isEmpty else {
    fputs("usage: sanitize-png.swift [--check] file.png [...]\n", stderr)
    exit(2)
}

var failed = false
for path in arguments {
    do {
        let url = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: url)
        let sanitized = try sanitizedPNG(original)

        if checkOnly {
            if sanitized != original {
                fputs("\(path): contains removable PNG metadata\n", stderr)
                failed = true
            }
        } else {
            try sanitized.write(to: url, options: [.atomic])
        }
    } catch {
        fputs("\(path): \(error.localizedDescription)\n", stderr)
        failed = true
    }
}

if failed {
    exit(1)
}

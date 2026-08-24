import Darwin
import Foundation
import Security

actor SecureShredderService {
    private let fm = FileManager.default

    init() {}

    /// Performs a permanent 3-pass cryptographic shred on a file with hardware sync.
    /// WARNING: This makes the file permanently unrecoverable.
    func shredFile(at fileURL: URL) throws {
        let path = fileURL.path
        guard fm.fileExists(atPath: path) else {
            throw NSError(domain: "SecureShredder", code: 1, userInfo: [NSLocalizedDescriptionKey: "File does not exist."])
        }

        let fileHandle = try FileHandle(forUpdating: fileURL)
        defer { try? fileHandle.close() }

        let fileSize = try fileHandle.seekToEnd()
        guard fileSize > 0 else {
            try fm.removeItem(at: fileURL)
            return
        }

        let chunkSize = 64 * 1024 // 64 KB chunks
        let iterations = Int((fileSize + UInt64(chunkSize) - 1) / UInt64(chunkSize))

        // --- Pass 1: Cryptographically Secure Random Bytes ---
        try fileHandle.seek(toOffset: 0)
        var randomBuffer = [UInt8](repeating: 0, count: chunkSize)
        for i in 0..<iterations {
            let currentChunkSize = min(chunkSize, Int(fileSize - UInt64(i * chunkSize)))
            _ = SecRandomCopyBytes(kSecRandomDefault, currentChunkSize, &randomBuffer)
            fileHandle.write(Data(bytes: randomBuffer, count: currentChunkSize))
        }
        try fileHandle.synchronize()

        // --- Pass 2: Alternating Bit Pattern (0xAA) ---
        try fileHandle.seek(toOffset: 0)
        let patternBuffer = [UInt8](repeating: 0xAA, count: chunkSize)
        for i in 0..<iterations {
            let currentChunkSize = min(chunkSize, Int(fileSize - UInt64(i * chunkSize)))
            fileHandle.write(Data(bytes: patternBuffer, count: currentChunkSize))
        }
        try fileHandle.synchronize()

        // --- Pass 3: Zero-Fill (0x00) & Hardware Full Sync ---
        try fileHandle.seek(toOffset: 0)
        let zeroBuffer = [UInt8](repeating: 0x00, count: chunkSize)
        for i in 0..<iterations {
            let currentChunkSize = min(chunkSize, Int(fileSize - UInt64(i * chunkSize)))
            fileHandle.write(Data(bytes: zeroBuffer, count: currentChunkSize))
        }
        try fileHandle.synchronize()

        // Force physical write through disk controller cache
        let fd = fileHandle.fileDescriptor
        _ = fcntl(fd, F_FULLFSYNC)

        try fileHandle.close()

        // Rename file to a random UUID to obscure original name in directory catalog
        let randomName = UUID().uuidString
        let parentDir = fileURL.deletingLastPathComponent()
        let renamedURL = parentDir.appendingPathComponent(randomName)
        try? fm.moveItem(at: fileURL, to: renamedURL)

        // Final unlink
        if fm.fileExists(atPath: renamedURL.path) {
            try fm.removeItem(at: renamedURL)
        } else if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }
}

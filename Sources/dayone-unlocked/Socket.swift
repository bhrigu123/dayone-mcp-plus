import Foundation

enum Socket {
    private static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
        return addr
    }

    private static func withSockaddr<T>(_ addr: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) -> T) -> T {
        withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { body($0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }

    static func listen(at path: String) throws -> Int32 {
        guard var addr = address(path) else { throw DatabaseError(description: "Socket path too long: \(path)") }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw DatabaseError(description: "socket() failed: errno \(errno)") }
        let previous = umask(0o077) // socket file readable/writable by this user only
        let bound = withSockaddr(&addr) { bind(fd, $0, $1) }
        umask(previous)
        guard bound == 0 else { throw DatabaseError(description: "bind(\(path)) failed: errno \(errno)") }
        guard Darwin.listen(fd, 16) == 0 else { throw DatabaseError(description: "listen() failed: errno \(errno)") }
        return fd
    }

    static func connect(to path: String) -> Int32? {
        guard var addr = address(path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        guard withSockaddr(&addr, { Darwin.connect(fd, $0, $1) }) == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    static func writeAll(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let n = write(fd, buffer.baseAddress! + offset, buffer.count - offset)
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }
}

/// Reads newline-delimited messages from a file descriptor.
struct LineReader {
    let fd: Int32
    private var buffer = Data()

    init(fd: Int32) {
        self.fd = fd
    }

    mutating func next() -> Data? {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer[buffer.startIndex..<newline]
                buffer = Data(buffer[(newline + 1)...])
                return Data(line)
            }
            var chunk = [UInt8](repeating: 0, count: 65_536)
            let n = read(fd, &chunk, chunk.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return buffer.isEmpty ? nil : { defer { buffer = Data() }; return buffer }() }
            buffer.append(contentsOf: chunk[0..<n])
        }
    }
}

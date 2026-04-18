import Foundation

struct BinaryWriter {
    private(set) var data = Data()

    mutating func writeBytes(_ bytes: [UInt8]) {
        data.append(contentsOf: bytes)
    }

    mutating func writeUInt64(_ value: UInt64) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt32(_ value: UInt32) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func writeUInt16(_ value: UInt16) {
        var value = value.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    mutating func writeInt64(_ value: Int64) {
        writeUInt64(UInt64(bitPattern: value))
    }

    mutating func writeInt32(_ value: Int32) {
        writeUInt32(UInt32(bitPattern: value))
    }

    mutating func writeInt16(_ value: Int16) {
        writeUInt16(UInt16(bitPattern: value))
    }

    mutating func writeString(_ value: String) {
        let bytes = Array(value.utf8)
        writeUInt64(UInt64(bytes.count))
        writeBytes(bytes)
    }
}

struct BinaryReader {
    let data: Data
    var offset = 0

    mutating func readBytes(count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else {
            throw BinaryReaderError.unexpectedEndOfFile
        }

        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: count)
        let bytes = Array(data[start..<end])
        offset += count
        return bytes
    }

    mutating func readUInt64() throws -> UInt64 {
        let value = try readFixedWidthInteger(UInt64.self)
        return UInt64(littleEndian: value)
    }

    mutating func readUInt32LE() throws -> UInt32 {
        let value = try readFixedWidthInteger(UInt32.self)
        return UInt32(littleEndian: value)
    }

    mutating func readUInt16LE() throws -> UInt16 {
        let value = try readFixedWidthInteger(UInt16.self)
        return UInt16(littleEndian: value)
    }

    mutating func readUInt64ArrayLE(count: Int) throws -> [UInt64] {
        try readFixedWidthIntegerArray(UInt64.self, count: count)
    }

    mutating func readUInt16ArrayLE(count: Int) throws -> [UInt16] {
        try readFixedWidthIntegerArray(UInt16.self, count: count)
    }

    mutating func readInt32ArrayLE(count: Int) throws -> [Int32] {
        try readFixedWidthIntegerArray(Int32.self, count: count)
    }

    mutating func readInt16ArrayLE(count: Int) throws -> [Int16] {
        try readFixedWidthIntegerArray(Int16.self, count: count)
    }

    mutating func readInt64() throws -> Int64 {
        Int64(bitPattern: try readUInt64())
    }

    mutating func readInt32LE() throws -> Int32 {
        Int32(bitPattern: try readUInt32LE())
    }

    mutating func readInt16LE() throws -> Int16 {
        Int16(bitPattern: try readUInt16LE())
    }

    mutating func readUInt64LE() throws -> UInt64 {
        try readUInt64()
    }

    mutating func readInt64LE() throws -> Int64 {
        try readInt64()
    }

    mutating func readString() throws -> String {
        let count = try readIntCount()
        let bytes = try readBytes(count: count)
        guard let string = String(bytes: bytes, encoding: .utf8) else {
            throw BinaryReaderError.invalidUTF8
        }
        return string
    }

    mutating func readIntCount() throws -> Int {
        let value = try readUInt64()
        guard value <= UInt64(Int.max) else {
            throw BinaryReaderError.countOutOfRange
        }
        return Int(value)
    }

    var isAtEnd: Bool {
        offset == data.count
    }

    private mutating func readFixedWidthInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let byteCount = MemoryLayout<T>.size
        guard offset + byteCount <= data.count else {
            throw BinaryReaderError.unexpectedEndOfFile
        }

        var value: T = 0
        let start = data.index(data.startIndex, offsetBy: offset)
        let end = data.index(start, offsetBy: byteCount)
        _ = withUnsafeMutableBytes(of: &value) { rawBuffer in
            data.copyBytes(to: rawBuffer, from: start..<end)
        }
        offset += byteCount
        return value
    }

    private mutating func readFixedWidthIntegerArray<T: FixedWidthInteger>(
        _ type: T.Type,
        count: Int
    ) throws -> [T] {
        let elementByteCount = MemoryLayout<T>.size
        guard offset <= data.count,
              count >= 0,
              count <= (data.count - offset) / elementByteCount else {
            throw BinaryReaderError.unexpectedEndOfFile
        }

        let currentOffset = offset
        offset += count * elementByteCount
        var values = Array<T>(unsafeUninitializedCapacity: count) { buffer, initializedCount in
            let rawBuffer = UnsafeMutableRawBufferPointer(buffer)
            let start = data.index(data.startIndex, offsetBy: currentOffset)
            let end = data.index(start, offsetBy: count * elementByteCount)
            data.copyBytes(to: rawBuffer, from: start..<end)
            initializedCount = count
        }

        #if _endian(little)
        return values
        #else
        for index in values.indices {
            values[index] = T(littleEndian: values[index])
        }
        return values
        #endif
    }
}

enum BinaryReaderError: Error {
    case unexpectedEndOfFile
    case invalidUTF8
    case countOutOfRange
}

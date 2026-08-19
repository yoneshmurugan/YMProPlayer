// RingBufferTests.swift
// ytsplayerTests

import XCTest

final class RingBufferTests: XCTestCase {

    func testWriteThenRead() {
        let rb = RingBuffer_Create(1024)!
        defer { RingBuffer_Destroy(rb) }

        var source: [Float] = (0..<10).flatMap { [Float($0), Float($0) + 0.5] } // 10 stereo frames
        let written = RingBuffer_Write(rb, &source, 10)
        XCTAssertEqual(written, 10, "Should write all 10 frames")

        var dest = [Float](repeating: 0, count: 20)
        let read = RingBuffer_Read(rb, &dest, 10)
        XCTAssertEqual(read, 10, "Should read all 10 frames back")
        XCTAssertEqual(dest[0], source[0], "First sample should match")
        XCTAssertEqual(dest[19], source[19], "Last sample should match")
    }

    func testWrapAround() {
        let rb = RingBuffer_Create(8)! // 8 frames
        defer { RingBuffer_Destroy(rb) }

        // Write 6 frames
        var src = [Float](repeating: 1.0, count: 12)
        _ = RingBuffer_Write(rb, &src, 6)

        // Read 5 to move the read pointer
        var dst = [Float](repeating: 0, count: 10)
        _ = RingBuffer_Read(rb, &dst, 5)

        // Write 7 more (wraps around the 8-frame buffer)
        var src2 = [Float](repeating: 2.0, count: 14)
        let written = RingBuffer_Write(rb, &src2, 7)
        XCTAssertEqual(written, 7, "Should fit 7 frames (1 remaining + ring capacity)")

        // Read all
        var dst2 = [Float](repeating: 0, count: 16)
        let read = RingBuffer_Read(rb, &dst2, 8)
        XCTAssertEqual(read, 8)
        XCTAssertEqual(dst2[0], 1.0) // the remaining frame from first write
        XCTAssertEqual(dst2[2], 2.0) // start of wrapped write
    }

    func testUnderrun() {
        let rb = RingBuffer_Create(1024)!
        defer { RingBuffer_Destroy(rb) }

        var dest = [Float](repeating: 0, count: 200)
        let read = RingBuffer_Read(rb, &dest, 100)
        XCTAssertEqual(read, 0, "Reading from empty buffer should return 0")
    }

    func testOverflow() {
        let rb = RingBuffer_Create(4)! // only 4 frames
        defer { RingBuffer_Destroy(rb) }

        var src = [Float](repeating: 1.0, count: 20)
        let written = RingBuffer_Write(rb, &src, 10)
        XCTAssertEqual(written, 4, "Should not write more than capacity")
    }

    func testReset() {
        let rb = RingBuffer_Create(16)!
        defer { RingBuffer_Destroy(rb) }

        var src = [Float](repeating: 1.0, count: 20)
        _ = RingBuffer_Write(rb, &src, 10)
        RingBuffer_Reset(rb)
        XCTAssertEqual(RingBuffer_AvailableToRead(rb), 0, "After reset, buffer should be empty")
    }
}

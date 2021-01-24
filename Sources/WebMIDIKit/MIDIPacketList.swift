//
//  MIDIPacketList.swift
//  WebMIDIKit
//
//  Created by Adam Nemecek on 2/3/17.
//
//

import AVFoundation

extension MIDIPacketList {
    /// this needs to be mutating since we are potentionally changint the timestamp
    /// we cannot make a copy since that woulnd't copy the whole list
    internal mutating func send(to output: MIDIOutput, offset: Double? = nil) {

        if let millisecondOffset = offset {
            let tickOffset: UInt64
            let current: UInt64
            #if os(macOS)
                current = AudioGetCurrentHostTime()
                tickOffset = AudioConvertNanosToHostTime(UInt64(millisecondOffset * 1_000_000))
            #else
                // see https://developer.apple.com/library/archive/qa/qa1643/_index.html
                // and https://developer.apple.com/documentation/driverkit/3433733-mach_timebase_info
                current = mach_absolute_time()
                var info = mach_timebase_info_data_t()
                mach_timebase_info(&info)
                let fraction = Double(info.numer) / Double(info.denom)
                let nanosecondOffset = millisecondOffset * 1_000_000
                tickOffset = UInt64(nanosecondOffset / fraction)
            #endif

            let ts = current + tickOffset
            packet.timeStamp = ts
        }

        OSAssert(MIDISend(output.ref, output.endpoint.ref, &self))
        /// this let's us propagate the events to everyone subscribed to this
        /// endpoint not just this port, i'm not sure if we actually want this
        /// but for now, it let's us create multiple ports from different MIDIAccess
        /// objects and have them all receive the same messages
        OSAssert(MIDIReceived(output.endpoint.ref, &self))
    }

    internal init<S: Sequence>(_ data: S, timestamp: MIDITimeStamp = 0) where S.Iterator.Element == UInt8 {
        self.init(packet: MIDIPacket(data, timestamp: timestamp))
    }

    internal init(packet: MIDIPacket) {
        self.init(numPackets: 1, packet: packet)
    }
}

extension UnsafeMutablePointer where Pointee == UInt8 {
    @inline(__always)
    init(ptr : UnsafeMutableRawBufferPointer) {
        self = ptr.baseAddress!.assumingMemoryBound(to: UInt8.self)
    }
}

extension MIDIPacket {
    @inline(__always)
    internal init<S: Sequence>(_ data: S, timestamp: MIDITimeStamp = 0) where S.Iterator.Element == UInt8 {
        self.init()

        timeStamp = timestamp

        let d = Data(data)
        length = UInt16(d.count)

        /// write out bytes to data
        withUnsafeMutableBytes(of: &self.data) {
            d.copyBytes(to: .init(ptr: $0), count: d.count)
        }

//        var ptr = UnsafeMutableRawBufferPointer(packet: &self)
    }
}

extension Data {
    @inline(__always)
    init(packet p: inout MIDIPacket) {
        self = Swift.withUnsafeBytes(of: &p.data) {
            .init(bytes: $0.baseAddress!, count: Int(p.length))
        }
    }
}

extension MIDIEvent {
    @inline(__always)
    fileprivate init(packet p: inout MIDIPacket) {
        timestamp = p.timeStamp
        data = .init(packet: &p)
    }
}

extension MIDIPacketList: Sequence {
    public typealias Element = MIDIEvent

    public func makeIterator() -> AnyIterator<Element> {
        var p: MIDIPacket = packet
        var i = (0..<numPackets).makeIterator()

        return AnyIterator {
            defer {
                p = withUnsafePointer(to: &p) { MIDIPacketNext($0).pointee }
            }

            return i.next().map { _ in .init(packet: &p) }
        }
    }
}

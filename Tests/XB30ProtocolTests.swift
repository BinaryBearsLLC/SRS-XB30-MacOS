import Foundation

@main struct XB30ProtocolTests {
    static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }

    static func main() {
        let volume = TandemCodec.frame(payload: [0x93, 0x01, 0x02, 0x19], dataType: 0, sequence: 0)
        precondition(hex(volume) == "3e00000000000493010219b33c")

        let decoder = TandemDecoder()
        let partial = decoder.push(volume.prefix(5))
        precondition(partial.frames.isEmpty && partial.errors.isEmpty)
        let decoded = decoder.push(volume.dropFirst(5))
        precondition(decoded.errors.isEmpty && decoded.frames.count == 1)
        precondition(decoded.frames[0].dataType == 0 && decoded.frames[0].sequence == 0)
        precondition(decoded.frames[0].payload == Data([0x93, 0x01, 0x02, 0x19]))

        let escaped = TandemCodec.frame(payload: [0x3c, 0x3d, 0x3e], dataType: 0, sequence: 1)
        precondition(hex(escaped).contains("3d2c3d2d3d2e"))
        let escapedDecoded = TandemDecoder().push(escaped)
        precondition(escapedDecoded.errors.isEmpty && escapedDecoded.frames[0].payload == Data([0x3c, 0x3d, 0x3e]))

        var session = TandemSession()
        precondition(session.beginDataFrame() == 0)
        precondition(session.beginDataFrame() == nil)
        precondition(session.receiveAck(sequence: 1))
        precondition(session.nextOutgoingSequence == 1 && !session.waitingForAck)
        precondition(TandemSession.acknowledgementSequence(for: 0) == 1)
        precondition(TandemSession.acknowledgementSequence(for: 1) == 0)

        var bootstrap = TandemBootstrap()
        precondition(bootstrap.start(hour: 12, minute: 34, second: 56) == [0x0f, 0x01])
        precondition(bootstrap.receiveAck(hour: 12, minute: 34, second: 56) == [0x01, 0x12, 0x34, 0x56])
        precondition(bootstrap.receiveAck(hour: 12, minute: 34, second: 56) == [0x05, 0x00, 0x00, 0x05])
        precondition(bootstrap.receiveAck(hour: 12, minute: 34, second: 56) == [0x0f, 0x02])
        precondition(bootstrap.receiveAck(hour: 12, minute: 34, second: 56) == nil)
        precondition(bootstrap.receiveLinkComplete() == [0x0f, 0x00])
        precondition(bootstrap.receiveAck(hour: 12, minute: 34, second: 56) == nil && bootstrap.isReady)

        // Every writable control exposed by the Mac UI has a stable, captured
        // Tandem payload.  These checks make the controller a reusable protocol
        // reference instead of an untested collection of button callbacks.
        precondition(XB30Command.volume(25) == [0x93, 0x01, 0x02, 0x19])
        precondition(XB30Command.autoStandby(false) == [0xf4, 0x12, 0x1f, 0xff, 0x01, 0x01, 0x00])
        precondition(XB30Command.autoStandby(true) == [0xf4, 0x12, 0x1f, 0xff, 0x01, 0x01, 0x01])
        precondition(XB30Command.autoStandbyPostWriteQuery == [0xf2, 0x12, 0x0f, 0xff])
        precondition(XB30Command.btStandby(true) == [0xf4, 0x12, 0x20, 0xff, 0x00, 0x00])
        precondition(XB30Command.btStandby(false) == [0xf4, 0x12, 0x21, 0xff, 0x00, 0x00])
        precondition(XB30Command.btStandbyPostWriteQuery == [0xf2, 0x12, 0x1f, 0xff])
        precondition(XB30Command.light(named: "RAVE") == [0xf4, 0x11, 0x11, 0xff, 0x00, 0x00])
        precondition(XB30Command.light(named: "CALM LIGHT BULB") == [0xf4, 0x11, 0x1c, 0xff, 0x00, 0x00])
        precondition(XB30Command.light(named: "invalid") == nil)
        precondition(XB30Command.preset(extraBass: false) == [0x93, 0x10, 0x00, 0xff, 0x00, 0x00])
        precondition(XB30Command.preset(extraBass: true) == [0x93, 0x10, 0x01, 0xff, 0x00, 0x00])
        precondition(XB30Command.equalizer(bass: -10, middle: 0, treble: 10) == [0x93, 0x10, 0x10, 0xff, 0x10, 0x06, 0x01, 0x01, 0x02, 0x0b, 0x03, 0x15])
        precondition(XB30Command.clearAudio(true) == [0x93, 0x11, 0xff, 0xff, 0x01, 0x01, 0x01])
        precondition(XB30Command.clearAudio(false) == [0x93, 0x10, 0x00, 0xff, 0x00, 0x00])
        precondition(XB30Command.codec(sbc: false) == [0xf4, 0x20, 0x01, 0x00, 0xff, 0x00, 0x00])
        precondition(XB30Command.codec(sbc: true) == [0xf4, 0x20, 0x01, 0x01, 0xff, 0x00, 0x00])
        precondition(XB30Command.batteryQuery == [0xf2, 0x12, 0x3f, 0xff])

        var state = XB30SettingsState()
        state.consume([0x92,0x11,0xff,0xff,0,0,1,1,1,1]);precondition(state.clearAudio == true && state.clearAudioEditable == false)
        state.consume([0x92,0x11,0xff,0xff,0,0,0,1,1,0]);precondition(state.clearAudio == false && state.clearAudioEditable == true)
        state.consume([0x07,0x01,0x04,0x31,0x2e,0x30,0x30])
        precondition(state.firmware == "1.00")
        state.consume([0x07,0x01,0x10,0x31])
        precondition(state.firmware == "1.00")
        state.consume([6,1,1,51]); precondition(state.volumeMaximum == 50)
        precondition(XB30Command.volume(-1).last == 0)
        state.consume([0x94, 0x01, 0x18])
        state.consume([0x92, 0x10, 0x10, 0xff, 0x00, 0x00, 0x00, 0x10, 0x06, 0x01, 0x0b, 0x02, 0x15, 0x03, 0x01])
        state.consume([0xf3, 0x11, 0x1c, 0xff, 0x00, 0x00, 0x00, 0x00])
        state.consume([0xf3, 0x12, 0x1f, 0xff, 0x00, 0x00, 0x01, 0x01, 0x01])
        state.consume([0xf3, 0x12, 0x20, 0xff, 0x00, 0x00])
        state.consume([0xf3, 0x12, 0x3f, 0xff, 0x00, 0x01, 0x21, 0x09, 0x41, 0x62, 0x6f, 0x75, 0x74, 0x20, 0x35, 0x30, 0x25])
        state.consume([0xf3, 0x20, 0x01, 0x01, 0xff, 0x00, 0x00, 0x00, 0x00])
        precondition(state.volume == 24 && state.bass == 0 && state.middle == 10 && state.treble == -10)
        // Captured real value reply versus frequency metadata: these must never
        // be confused when enabling the UI after bootstrap.
        let eqValues: [UInt8] = [0x92,0x10,0x1f,0xff,0,0,0,0x10,6,1,0x0b,2,0x0b,3,0x0b]
        let eqFrequencies: [UInt8] = [0x92,0x10,0x1f,0xff,1,3,1,0,0x64,2,1,0x4a,3,3,0xe8]
        precondition(XB30Command.matches(query:XB30Command.eqQuery,response:eqValues))
        precondition(!XB30Command.matches(query:XB30Command.eqQuery,response:eqFrequencies))
        state.consume(eqValues)
        precondition(state.bass == 0 && state.middle == 0 && state.treble == 0)
        precondition(!XB30Command.matches(query:XB30Command.batteryQuery,response:[0xf3,0x12,0x21,0xff,0,0]))
        precondition(XB30Command.volume(500).last == 50)
        precondition(TandemDecoder().push(TandemCodec.frame(payload:[],dataType:0,sequence:2)).frames.isEmpty)
        precondition(state.lightingID == 0x1c && state.autoStandby == true && state.btStandby == true && state.batteryText == "About 50%" && state.codecID == 1)
        var queue = LatestCommandQueue<Int>()
        queue.put("volume", 10); queue.put("light", 2); queue.put("volume", 80)
        precondition(queue.pop()?.1 == 80)
        precondition(queue.pop()?.0 == "light")
        precondition(queue.isEmpty && queue.pop() == nil)
        queue.put("eq", 4); queue.removeAll(); precondition(queue.isEmpty)
        print("XB30 Swift protocol and coalescing tests: OK")
    }
}

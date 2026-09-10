import SwiftUI
import IOBluetooth
import IOKit
import Combine
import Darwin

struct TandemFrame {
    let dataType: UInt8
    let sequence: UInt8
    let payload: Data
}

enum TandemCodec {
    static let start: UInt8 = 0x3e
    static let end: UInt8 = 0x3c
    static let escape: UInt8 = 0x3d

    static func frame(payload: [UInt8], dataType: UInt8, sequence: UInt8) -> Data {
        var body = [dataType, sequence]
        let count = UInt32(payload.count)
        body += [UInt8((count >> 24) & 0xff), UInt8((count >> 16) & 0xff), UInt8((count >> 8) & 0xff), UInt8(count & 0xff)]
        body += payload
        body.append(body.reduce(0, { ($0 &+ $1) }))
        var wire: [UInt8] = [start]
        for byte in body {
            switch byte {
            case end: wire += [escape, 0x2c]
            case escape: wire += [escape, 0x2d]
            case start: wire += [escape, 0x2e]
            default: wire.append(byte)
            }
        }
        wire.append(end)
        return Data(wire)
    }
}

final class TandemDecoder {
    private var active = false
    private var escaping = false
    private var body: [UInt8] = []
    func reset() { active = false; escaping = false; body = [] }

    func push(_ data: Data) -> (frames: [TandemFrame], errors: [String]) {
        var frames: [TandemFrame] = []
        var errors: [String] = []
        for byte in data {
            if body.count > 65542 { reset(); errors.append("Frame exceeds the 64 KiB limit") }
            if !active {
                if byte == TandemCodec.start { active = true; escaping = false; body = [] }
                continue
            }
            if byte == TandemCodec.start { escaping = false; body = []; continue }
            if byte == TandemCodec.end {
                if escaping { errors.append("Frame ends after an escape byte") }
                else if let frame = parse(body) { frames.append(frame) }
                else { errors.append("Invalid Tandem frame (length or checksum)") }
                active = false; escaping = false; body = []
                continue
            }
            if escaping {
                let decoded: UInt8?
                switch byte { case 0x2c: decoded = 0x3c; case 0x2d: decoded = 0x3d; case 0x2e: decoded = 0x3e; default: decoded = nil }
                guard let decoded else { errors.append("Invalid Tandem escape"); active = false; escaping = false; body = []; continue }
                body.append(decoded); escaping = false
            } else if byte == TandemCodec.escape { escaping = true }
            else { body.append(byte) }
        }
        return (frames, errors)
    }

    private func parse(_ bytes: [UInt8]) -> TandemFrame? {
        guard bytes.count >= 7, bytes[0] <= 1, bytes[1] <= 1 else { return nil }
        let length = bytes[2...5].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard bytes.count == Int(length) + 7 else { return nil }
        let checksum = bytes.dropLast().reduce(UInt8(0), { $0 &+ $1 })
        guard checksum == bytes.last else { return nil }
        return TandemFrame(dataType: bytes[0], sequence: bytes[1], payload: Data(bytes[6..<(bytes.count - 1)]))
    }
}

struct TandemSession {
    private(set) var nextOutgoingSequence: UInt8 = 0
    private(set) var waitingForAck = false

    mutating func beginDataFrame() -> UInt8? {
        guard !waitingForAck else { return nil }
        waitingForAck = true
        return nextOutgoingSequence
    }

    mutating func receiveAck(sequence: UInt8) -> Bool {
        guard waitingForAck, sequence <= 1, sequence != nextOutgoingSequence else { return false }
        nextOutgoingSequence = sequence
        waitingForAck = false
        return true
    }

    mutating func cancelPendingWrite() { waitingForAck = false }
    mutating func reset() { nextOutgoingSequence = 0; waitingForAck = false }
    static func acknowledgementSequence(for incomingSequence: UInt8) -> UInt8 { 1 - incomingSequence }
}

struct TandemBootstrap {
    enum Phase { case idle, startSent, clockSent, settingSent, receiveSent, waitingCapabilities, endSent, ready }
    private(set) var phase: Phase = .idle

    var isIdle: Bool { phase == .idle }
    var isReady: Bool { phase == .ready }

    mutating func start(hour: Int, minute: Int, second: Int) -> [UInt8]? {
        guard phase == .idle else { return nil }
        phase = .startSent
        return [0x0f, 0x01] // CONNECT_INITIAL_LINK: START_SENDING_APP_INFO
    }

    mutating func receiveAck(hour: Int, minute: Int, second: Int) -> [UInt8]? {
        switch phase {
        case .startSent:
            phase = .clockSent
            return [0x01, bcd(hour), bcd(minute), bcd(second)] // CONNECT_CLOCK_INFO
        case .clockSent:
            phase = .settingSent
            return [0x05, 0x00, 0x00, 0x05] // CONNECT_SETTING_INFO: not reading, content off, Italian
        case .settingSent:
            phase = .receiveSent
            return [0x0f, 0x02] // CONNECT_INITIAL_LINK: START_RECEIVING_ACC_INFO
        case .receiveSent:
            phase = .waitingCapabilities
            return nil
        case .endSent:
            phase = .ready
            return nil
        default:
            return nil
        }
    }

    mutating func receiveLinkComplete() -> [UInt8]? {
        guard phase == .waitingCapabilities else { return nil }
        phase = .endSent
        return [0x0f, 0x00] // CONNECT_INITIAL_LINK: END_EXCHANGING_CAPABILITIES
    }

    mutating func reset() { phase = .idle }

    private func bcd(_ value: Int) -> UInt8 {
        let bounded = max(0, min(value, 99))
        return UInt8((bounded / 10) << 4 | bounded % 10)
    }
}

struct XB30SettingsState {
    var volume: Int?
    var volumeMaximum: Int?
    var autoStandby: Bool?
    var btStandby: Bool?
    var lightingID: UInt8?
    var presetID: UInt8?
    var clearAudio: Bool?
    var clearAudioEditable: Bool?
    var bass: Int?
    var middle: Int?
    var treble: Int?
    var codecID: UInt8?
    var batteryText: String?
    var firmware: String?

    mutating func consume(_ payload: [UInt8]) {
        guard let command = payload.first else { return }
        switch command {
        case 0x06 where payload.count == 4 && payload[1] == 0x01 && payload[2] == 0x01 && payload[3] > 1:
            // Legacy Music Center: capability is a level count, including zero.
            volumeMaximum = Int(payload[3]) - 1
        case 0x07 where payload.count >= 3 && payload[1] == 0x01:
            let length=Int(payload[2])
            if length > 0, payload.count >= 3+length { firmware=String(bytes:payload[3..<(3+length)],encoding:.utf8) }
        case 0x94 where payload.count == 3 && payload[1] == 0x01:
            volume = Int(payload[2])
        case 0x92 where payload.count == 3 && payload[1] == 0x01:
            volume = Int(payload[2])
        case 0x92 where payload.count >= 4 && payload[1] == 0x10:
            if payload[2] == 0 || payload[2] == 1 { presetID = payload[2] }
            if payload.count >= 15, payload[4] == 0, let marker = payload.indices.first(where: { $0 + 7 < payload.count && payload[$0] == 0x10 && payload[$0 + 1] == 0x06 }) {
                let triples = payload[(marker + 2)...]
                for index in stride(from: triples.startIndex, to: triples.endIndex - 1, by: 2) {
                    let band = triples[index], encoded = triples[index + 1]
                    switch band { case 0x01: bass = Int(encoded) - 11; case 0x02: middle = Int(encoded) - 11; case 0x03: treble = Int(encoded) - 11; default: break }
                }
            }
        case 0x92 where payload.count == 10 && payload[1] == 0x11 && payload[7] == 1 && payload[8] == 1:
            clearAudio = payload[9] == 1
            clearAudioEditable = payload[6] == 0 // Music Center EnableDisableId, not the on/off value.
        case 0xf3 where payload.count >= 4 && payload[1] == 0x11:
            lightingID = payload[2]
        case 0xf3 where payload.count >= 4 && payload[1] == 0x12:
            switch payload[2] {
            case 0x1f: autoStandby = payload.last == 1
            case 0x20: btStandby = true
            case 0x21: btStandby = false
            case 0x3f:
                if let marker = payload.indices.first(where: { payload[$0] == 0x21 }), marker + 1 < payload.count {
                    let count = Int(payload[marker + 1]), start = marker + 2
                    if start + count <= payload.count { batteryText = String(bytes: payload[start..<(start + count)], encoding: .utf8) }
                }
            default: break
            }
        case 0xf3 where payload.count >= 4 && payload[1] == 0x20 && payload[2] == 0x01:
            codecID = payload[3]
        default:
            break
        }
    }
}

// Command builders are deliberately independent from SwiftUI.  The byte values
// below come from the captured XB30 Tandem exchange and are covered by the
// offline protocol tests, so a UI refactor cannot silently change the wire API.
enum XB30Command {
    static let lightNames = ["LIGHT OFF", "RAVE", "CHILL", "RANDOM FLASH OFF", "HOT", "COOL", "STROBE", "CALM MAGENTA", "CALM CYAN", "CALM LIME", "CALM CINNABAR", "CALM DAYLIGHT", "CALM LIGHT BULB"]

    static func volume(_ value: Int, maximum: Int = 50) -> [UInt8] { [0x93, 0x01, 0x02, UInt8(clamping:max(0,min(maximum,value))) ] }
    static func autoStandby(_ enabled: Bool) -> [UInt8] { [0xf4, 0x12, 0x1f, 0xff, 0x01, 0x01, enabled ? 1 : 0] }
    static func btStandby(_ enabled: Bool) -> [UInt8] { [0xf4, 0x12, enabled ? 0x20 : 0x21, 0xff, 0x00, 0x00] }
    // Music Center uses these broad post-write queries, distinct from the
    // narrower discovery reads (1F and 2F) made during bootstrap.
    static let autoStandbyPostWriteQuery: [UInt8] = [0xf2, 0x12, 0x0f, 0xff]
    static let btStandbyPostWriteQuery: [UInt8] = [0xf2, 0x12, 0x1f, 0xff]
    static func light(named name: String) -> [UInt8]? {
        guard let index = lightNames.firstIndex(of: name) else { return nil }
        return [0xf4, 0x11, UInt8(0x10 + index), 0xff, 0x00, 0x00]
    }
    static func preset(extraBass: Bool) -> [UInt8] { [0x93, 0x10, extraBass ? 1 : 0, 0xff, 0x00, 0x00] }
    static func equalizer(bass: Int, middle: Int, treble: Int) -> [UInt8] {
        [0x93, 0x10, 0x10, 0xff, 0x10, 0x06, 0x01, UInt8(max(-10,min(10,bass)) + 11), 0x02, UInt8(max(-10,min(10,middle)) + 11), 0x03, UInt8(max(-10,min(10,treble)) + 11)]
    }
    static func clearAudio(_ enabled: Bool) -> [UInt8] {
        // Music Center disables ClearAudio+ by selecting FLAT, not by sending a
        // guessed direct "off" value.
        enabled ? [0x93, 0x11, 0xff, 0xff, 0x01, 0x01, 0x01] : preset(extraBass: false)
    }
    static func codec(sbc: Bool) -> [UInt8] { [0xf4, 0x20, 0x01, sbc ? 1 : 0, 0xff, 0x00, 0x00] }

    static let batteryQuery: [UInt8] = [0xf2, 0x12, 0x3f, 0xff]
    static let eqQuery: [UInt8] = [0x91, 0x10, 0x1f, 0xff, 0x00]
    static func matches(query q: [UInt8], response p: [UInt8]) -> Bool {
        guard q.count >= 2, p.count >= 3 else { return false }
        if q[0] == 0x91 {
            guard p[0] == 0x92, p[1] == q[1] else { return false }
            if q == eqQuery { return p.count >= 15 && p[4] == 0 && p[7] == 0x10 && p[8] == 6 }
            if q[1] == 0x10 { return p.count >= 5 && p[4] == 0 && (p[2] == 0 || p[2] == 1 || p[2] == 0x10) }
            return true
        }
        guard q[0] == 0xf2, p[0] == 0xf3, q[1] == p[1], q.count >= 4 else { return false }
        if q[1] == 0x11 { return (0x10...0x1c).contains(p[2]) }
        if q[1] == 0x20 { return p.count >= 5 && p[2] == q[2] }
        if q == batteryQuery { return p[2] == 0x3f }
        if q[2] == 0x2f { return p[2] == 0x20 || p[2] == 0x21 }
        return p[2] == 0x1f
    }
}

final class XB30Transport: NSObject, ObservableObject {
    @Published private(set) var status = "Disconnected"
    @Published private(set) var connected = false
    @Published private(set) var connecting = false
    @Published private(set) var ready = false
    @Published private(set) var failed = false
    var onFrame: ((TandemFrame) -> Void)?
    var onLog: ((String) -> Void)?
    @Published private(set) var busy = false
    @Published private(set) var restoringRadio = false

    #if UI_REVIEW
    func reviewStatus(_ value: String) { status=value }
    func reviewBusy(_ value: Bool) { busy=value }
    func reviewState(connected value: Bool) { connected=value;ready=value;status=value ? "UI fixture — no Bluetooth commands" : "Disconnected" }
    #endif
    private let linkQueue = DispatchQueue(label:"com.binarybears.xb30.link",qos:.userInitiated)
    private var localChannelID: BluetoothRFCOMMChannelID = 0
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var localRecord: IOBluetoothSDPServiceRecord?
    private var incomingNotification: IOBluetoothUserNotification?
    private var session = TandemSession()
    private var bootstrap = TandemBootstrap()
    private var initialReadsStarted = false
    private var initialReads: [[UInt8]] = []
    private var initialPending: [UInt8]?
    private var queryPending: [UInt8]?
    private var readbackTriggered = false
    private var postAckQuery: [UInt8]?
    private var transactionID = 0
    private struct Readback {
        let notification: UInt8
        let notificationGroup: UInt8
        let query: [UInt8]
        let queryResponse: UInt8
    }
    private var pendingReadback: Readback?
    private var awaitingReadbackResponse: UInt8?
    private var acknowledgementTimeout: DispatchWorkItem?
    private var readbackTimeout: DispatchWorkItem?
    private let decoder = TandemDecoder()
    private var writeBuffers: [UnsafeMutableRawPointer: NSData] = [:]

    // Retain each buffer until the asynchronous RFCOMM completion callback.
    private func writeWire(_ wire: Data, channel: IOBluetoothRFCOMMChannel) -> IOReturn {
        onLog?("WIRE TX "+wire.map { String(format:"%02x",$0) }.joined())
        let buffer = wire as NSData
        let token = UnsafeMutableRawPointer(Unmanaged.passUnretained(buffer).toOpaque())
        writeBuffers[token] = buffer
        let result = channel.writeAsync(UnsafeMutableRawPointer(mutating: buffer.bytes), length: UInt16(buffer.length), refcon: token)
        if result != kIOReturnSuccess { writeBuffers.removeValue(forKey: token) }
        return result
    }

    @objc func rfcommChannelWriteComplete(_ source: IOBluetoothRFCOMMChannel!, refcon: UnsafeMutableRawPointer!, status result: IOReturn) {
        if let refcon { writeBuffers.removeValue(forKey: refcon) }
        guard source === channel, result != kIOReturnSuccess else { return }
        disconnect(); failed=true
        status = "Bluetooth write failed (\(result)). Reconnect the speaker."
    }

    @objc func connectionComplete(_ source: IOBluetoothDevice!, status result: IOReturn) {
        guard source === device else { return }
        onLog?("ACL completion result=\(result), connected=\(source.isConnected())")
        guard result != kIOReturnSuccess else { return }
        connecting=false;failed=true
        status = "Bluetooth connection failed (\(result)). Make sure the speaker is on."
    }

    func connect(reconnectAudio: Bool = false) {
        disconnect()
        guard let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
              let xb30 = devices.first(where: { $0.name == "SRS-XB30" }) else {
            failed=true
            status = "SRS-XB30 is not paired. Pair it in Bluetooth Settings and try again."
            return
        }
        device = xb30
        let service: [String: Any] = [
            "0001": [Data([0x91,0x81,0x9d,0x50,0x5d,0x72,0x44,0x78,0xa0,0x01,0x29,0xeb,0x2c,0x76,0x35,0x68])],
            "0004": [[Data([0x01,0x00])], [Data([0x00,0x03]), ["DataElementType":1,"DataElementSize":1,"DataElementValue":7]]],
            "0005": [Data([0x10,0x02])],
            "0100": "com.sony.songpal.tandem"
        ]
        if localRecord == nil { localRecord = IOBluetoothSDPServiceRecord.publishedServiceRecord(with: service) }
        guard let localRecord else { status = "Could not publish the Tandem service on this Mac."; return }
        var channelID: BluetoothRFCOMMChannelID = 0
        guard localRecord.getRFCOMMChannelID(&channelID) == kIOReturnSuccess else { status = "No local Tandem channel was assigned."; return }
        localChannelID = channelID
        if incomingNotification == nil {
            incomingNotification = IOBluetoothRFCOMMChannel.register(forChannelOpenNotifications: self, selector: #selector(incoming(_:channel:)), withChannelID: channelID, direction: kIOBluetoothUserNotificationChannelDirectionIncoming)
        }
        onLog?("Tandem listener channel=\(channelID), registered=\(incomingNotification != nil), ACL=\(xb30.isConnected())")
        status = incomingNotification != nil ? "Listening for Tandem on this Mac (channel \(channelID)). Reconnect the speaker to this Mac to start the session." : "Could not register the incoming Tandem channel."
        if reconnectAudio, incomingNotification != nil {
            let id = transactionID
            connecting = true
            status = "Connecting to XB30…"
            linkQueue.async { [weak self] in
                let closeResult = xb30.closeConnection()
                DispatchQueue.main.async {
                    guard let self, self.transactionID == id else { return }
                    self.onLog?("ACL close result=\(closeResult)")
                    guard closeResult == kIOReturnSuccess else { self.connecting=false;self.failed=true;self.status="Could not disconnect the previous Bluetooth session.";return }
                    self.openAfterDisconnection(xb30,transaction:id)
                }
            }
            DispatchQueue.main.asyncAfter(deadline:.now()+35) { [weak self] in
                guard let self, self.transactionID == id, !self.connected else { return }
                self.connecting = false; self.failed = true
                self.status = "No Tandem session reached the app. Close other control apps and retry, or use Bluetooth recovery in Device Settings."
            }
        }
    }

    private func openAfterDisconnection(_ xb30: IOBluetoothDevice, transaction id: Int, attempts: Int = 0, retry: Int = 0) {
        guard transactionID == id else { return }
        // closeConnection can return before bluetoothd releases ACL. Never race that teardown.
        if xb30.isConnected() {
            guard attempts < 50 else { connecting=false;failed=true;status="The previous Bluetooth session is still closing. Retry Connect.";return }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.2) { [weak self] in self?.openAfterDisconnection(xb30,transaction:id,attempts:attempts+1,retry:retry) }
            return
        }
        onLog?("ACL disconnected confirmed after \(attempts) checks; opening on worker queue")
        linkQueue.async { [weak self] in
            let result=xb30.openConnection()
            DispatchQueue.main.async {
                guard let self, self.transactionID == id else { return }
                self.onLog?("ACL open completed result=\(result), connected=\(xb30.isConnected())")
                if result != kIOReturnSuccess {
                    if retry < 2 {
                        self.onLog?("Retrying ACL after transient open failure (attempt \(retry+2))")
                        DispatchQueue.main.asyncAfter(deadline:.now()+1.5) { [weak self] in
                            self?.openAfterDisconnection(xb30,transaction:id,retry:retry+1)
                        }
                    } else { self.connecting=false;self.failed=true;self.status="Bluetooth connection failed (\(result)). Check the speaker and retry Connect." }
                }
            }
        }
    }

    func restoreBluetooth() {
        guard !restoringRadio else { return }
        typealias Setter = @convention(c) (Int32) -> Void
        typealias Getter = @convention(c) () -> Int32
        guard let setterSymbol = dlsym(UnsafeMutableRawPointer(bitPattern:-2),"IOBluetoothPreferenceSetControllerPowerState"),
              let getterSymbol = dlsym(UnsafeMutableRawPointer(bitPattern:-2),"IOBluetoothPreferenceGetControllerPowerState") else {
            status = "Radio recovery is unavailable on this macOS. Turn Bluetooth off and on in System Settings."; return
        }
        let setter = unsafeBitCast(setterSymbol,to:Setter.self)
        let getter = unsafeBitCast(getterSymbol,to:Getter.self)
        disconnect(); incomingNotification?.unregister(); incomingNotification=nil; localRecord = nil; restoringRadio = true
        status = "Restarting Bluetooth. Accessories will disconnect briefly…"
        setter(0)
        DispatchQueue.main.asyncAfter(deadline:.now()+2) { [weak self] in
            setter(1)
            DispatchQueue.main.asyncAfter(deadline:.now()+2) {
                guard let self else { return }
                self.restoringRadio = false
                guard getter() == 1 else { self.status = "Bluetooth could not be turned back on. Enable it in System Settings."; return }
                self.connect(reconnectAudio:true)
            }
        }
    }

    func disconnect() {
        transactionID += 1; failed = false; connecting = false
        // Keep the listener registered for the lifetime of the local service.
        // A new registration on the same channel can miss callbacks on macOS.
        // Reuse this process's local record: current macOS can fail to remove it
        // while returning success, so reconnect must not publish duplicates.
        let closingChannel = channel
        channel = nil
        if let closingChannel { _ = closingChannel.close() }
        acknowledgementTimeout?.cancel(); readbackTimeout?.cancel(); pendingReadback = nil; awaitingReadbackResponse = nil
        channel = nil; device = nil; connected = false; ready = false; session.reset(); bootstrap.reset(); initialReadsStarted = false; initialReads = []; status = "Disconnected"
        decoder.reset(); initialPending = nil; queryPending = nil; postAckQuery = nil; readbackTriggered = false; busy = false
    }

    func send(_ payload: [UInt8], notification: UInt8? = nil, readback: [UInt8]? = nil, readbackResponse: UInt8? = nil) {
        guard ready else { status = "Command not sent: the Tandem session is not ready."; return }
        guard !busy else { status = "Waiting for the previous command response."; return }
        busy = true
        transactionID += 1
        guard pendingReadback == nil && awaitingReadbackResponse == nil else { status = "Command not sent: the previous change is still being verified."; return }
        if let notification, let readback, let readbackResponse {
            pendingReadback = Readback(notification: notification, notificationGroup: payload[1], query: readback, queryResponse: readbackResponse)
        }
        if notification == nil, let readback { postAckQuery = readback }
        if payload.first == 0x91 || payload.first == 0xf2 { queryPending = payload }
        if !writeData(payload) { pendingReadback = nil; queryPending = nil; busy = false }
        else { armResponseTimeout() }
    }

    @discardableResult private func writeData(_ payload: [UInt8]) -> Bool {
        guard let channel, connected else { status = "Command not sent: Tandem is disconnected."; return false }
        guard let sequence = session.beginDataFrame() else { status = "Waiting for the previous Tandem acknowledgement."; return false }
        let wire = TandemCodec.frame(payload: payload, dataType: 0x00, sequence: sequence)
        onLog?("TX " + payload.map { String(format:"%02x",$0) }.joined())
        let result = writeWire(wire, channel: channel)
        if result == kIOReturnSuccess {
            status = "Sent payload: \(payload.map { String(format: "%02X", $0) }.joined(separator: " "))"
            acknowledgementTimeout?.cancel()
            let expectedSequence = sequence
            let timeout = DispatchWorkItem { [weak self] in
                guard let self, self.session.waitingForAck else { return }
                self.session.cancelPendingWrite()
                self.pendingReadback = nil
                self.awaitingReadbackResponse = nil
                self.status = "Timeout ACK Tandem (sequence \(expectedSequence)). Check the Bluetooth connection and retry."
                self.ready = false; self.busy = false; self.failed = true; self.connecting = false
            }
            acknowledgementTimeout = timeout
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
            return true
        } else {
            session.cancelPendingWrite();ready=false;failed=true;connecting=false
            status = "RFCOMM write failed (IOReturn \(result))."
            return false
        }
    }

    private func clockComponents() -> (Int, Int, Int) {
        let values = Calendar.current.dateComponents([.hour, .minute, .second], from: Date())
        return (values.hour ?? 0, values.minute ?? 0, values.second ?? 0)
    }

    private func continueBootstrapAfterAck() {
        if session.waitingForAck { return }
        if readbackTriggered, let readback = pendingReadback { readbackTriggered = false; startReadback(readback); return }
        if ready {
            if pendingReadback != nil {
                let id = transactionID
                DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { [weak self] in
                    guard let self, self.transactionID == id, self.ready, !self.session.waitingForAck, let readback = self.pendingReadback else { return }
                    self.startReadback(readback)
                }
            }
            if let query = postAckQuery {
                postAckQuery = nil; queryPending = query
                let id = transactionID
                let delay: Double = query.prefix(2) == [0xf2,0x20] ? 0.5 : 0.12
                DispatchQueue.main.asyncAfter(deadline:.now()+delay) { [weak self] in
                    guard let self, self.transactionID == id, self.connected, self.queryPending == query else { return }
                    self.writeData(query); self.armResponseTimeout()
                }
            } else if pendingReadback == nil && queryPending == nil { busy = false }
            return
        }
        let now = clockComponents()
        if let payload = bootstrap.receiveAck(hour: now.0, minute: now.1, second: now.2) { writeData(payload) }
        guard bootstrap.isReady else { return }
        if !initialReadsStarted {
            initialReadsStarted = true
            initialReads = [
                [0x91, 0x01],                         // volume
                [0x91, 0x11, 0xff, 0xff, 0x00],       // ClearAudio+
                [0x91, 0x10, 0x0f, 0xff, 0x00],       // preset EQ
                XB30Command.eqQuery,                  // actual BASS/MID/TRE values
                [0xf2, 0x12, 0x1f, 0xff],             // Auto Standby
                [0xf2, 0x12, 0x2f, 0xff],             // BT Standby
                [0xf2, 0x12, 0x3f, 0xff],             // battery text
                [0xf2, 0x11, 0x1f, 0xff],             // lighting mode
                [0xf2, 0x20, 0x01, 0x0f, 0xff],       // Bluetooth codec
            ]
        }
        guard initialPending == nil else { return }
        if let next = initialReads.first {
            initialReads.removeFirst()
            initialPending = next
            status = "Session ready. Reading settings…"
            writeData(next)
            armResponseTimeout()
        } else {
            ready = true; failed = false; connecting = false
            status = "Settings have been read from the speaker."
        }
    }

    private func beginBootstrapIfNeeded() {
        guard bootstrap.isIdle else { return }
        let now = clockComponents()
        if let payload = bootstrap.start(hour: now.0, minute: now.1, second: now.2) {
            status = "XB30 found. Starting the control session…"
            let activeChannel=channel
            DispatchQueue.main.asyncAfter(deadline:.now()+20) { [weak self] in
                guard let self, self.channel === activeChannel, !self.ready, !self.failed else { return }
                self.disconnect();self.failed=true
                self.status="The speaker did not finish synchronization. Retry Connect; if this repeats, turn the speaker off and on."
            }
            writeData(payload)
        }
    }

    private func acknowledgeIncoming(sequence: UInt8) {
        guard let channel, connected else { return }
        let wire = TandemCodec.frame(payload: [], dataType: 0x01, sequence: TandemSession.acknowledgementSequence(for: sequence))
        if writeWire(wire, channel: channel) != kIOReturnSuccess {
            disconnect(); failed=true; status = "Bluetooth acknowledgement failed. Reconnect the speaker."
        }
    }

    private func startReadback(_ readback: Readback) {
        pendingReadback = nil
        awaitingReadbackResponse = readback.queryResponse
        queryPending = readback.query
        status = "Change acknowledged. Reading the speaker state…"
        guard writeData(readback.query) else { awaitingReadbackResponse = nil; ready = false; busy = false; failed = true; return }
        readbackTimeout?.cancel()
        let expectedResponse = readback.queryResponse
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.awaitingReadbackResponse == expectedResponse else { return }
            self.awaitingReadbackResponse = nil
                self.status = "Readback timed out. The change may have applied, but it could not be verified. Reconnect to read the current state."
                self.ready = false; self.busy = false; self.failed = true; self.connecting = false
        }
        readbackTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: timeout)
    }

    private func armResponseTimeout() {
        readbackTimeout?.cancel()
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.initialPending != nil || self.busy else { return }
            self.ready = false; self.busy = false; self.failed = true; self.connecting = false
            self.status = "Speaker response timed out. Reconnect before making more changes."
        }
        readbackTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline:.now()+8,execute:timeout)
    }

    @objc func incoming(_ notification: IOBluetoothUserNotification!, channel opened: IOBluetoothRFCOMMChannel!) {
        onLog?("RFCOMM callback channel=\(opened?.getID() ?? 0), incoming=\(opened?.isIncoming() ?? false)")
        guard let opened, let device, opened.getDevice().addressString == device.addressString, opened.getID() == localChannelID, opened.isIncoming() else { return }
        guard channel == nil else { opened.close(); return }
        acknowledgementTimeout?.cancel(); readbackTimeout?.cancel(); pendingReadback = nil; awaitingReadbackResponse = nil
        channel = opened; connected = true; ready = false; failed = false; session.reset(); bootstrap.reset(); initialReadsStarted = false; initialReads = []; status = "Tandem connected. Waiting for the speaker handshake."
        let delegateResult=opened.setDelegate(self)
        onLog?("RFCOMM delegate installed result=\(delegateResult)")
        let id = transactionID
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.transactionID == id, self.connected, !self.ready else { return }
            self.disconnect(); self.failed = true
            self.status = "Initial synchronization timed out. Reconnect the speaker."
        }
    }

    @objc func rfcommChannelData(_ channel: IOBluetoothRFCOMMChannel!, data dataPointer: UnsafeMutableRawPointer!, length dataLength: Int) {
        guard self.channel === channel else { onLog?("Ignoring data from a stale RFCOMM channel");return }
        let bytes=Data(bytes:dataPointer,count:dataLength)
        onLog?("WIRE RX "+bytes.map { String(format:"%02x",$0) }.joined())
        let result = decoder.push(bytes)
        if let error = result.errors.first { status = "Discarded frame: \(error)" }
        for frame in result.frames {
            let payload = [UInt8](frame.payload)
            onLog?("RX \(frame.dataType == 1 ? "ACK" : payload.map { String(format:"%02x",$0) }.joined())")
            if frame.dataType == 0x01 {
                if session.receiveAck(sequence: frame.sequence) { acknowledgementTimeout?.cancel(); continueBootstrapAfterAck() }
            } else if frame.dataType == 0x00 {
                acknowledgeIncoming(sequence: frame.sequence)
                if payload.first == 0x00 { beginBootstrapIfNeeded() } // CONNECT_REQ from XB30
                if payload.first == 0x03, let end = bootstrap.receiveLinkComplete() { writeData(end) } // CONNECT_LINK_COMPLETE
                if let readback = pendingReadback, payload.first == readback.notification, payload.count > 1, payload[1] == readback.notificationGroup {
                    if session.waitingForAck { readbackTriggered = true } else { startReadback(readback) }
                }
                else if let query = queryPending, XB30Command.matches(query:query,response:payload) {
                    awaitingReadbackResponse = nil
                    queryPending = nil; busy = session.waitingForAck
                    readbackTimeout?.cancel()
                    status = "Speaker state verified."
                }
            }
            onFrame?(frame)
            if frame.dataType == 0, let query = initialPending, XB30Command.matches(query:query,response:payload) {
                initialPending = nil; readbackTimeout?.cancel(); continueBootstrapAfterAck()
            }
        }
    }

    @objc func rfcommChannelClosed(_ channel: IOBluetoothRFCOMMChannel!) {
        guard self.channel === channel else { return }
        self.channel = nil; transactionID += 1; connecting=false;failed=true
        acknowledgementTimeout?.cancel(); readbackTimeout?.cancel(); pendingReadback = nil; awaitingReadbackResponse = nil
        initialPending=nil; queryPending=nil; postAckQuery=nil; readbackTriggered=false; busy=false; decoder.reset()
        connected = false; ready = false; session.reset(); bootstrap.reset(); initialReadsStarted = false; initialReads = []; status = "The speaker closed the control connection."
    }
}

// Coalesce unsent edits by control while preserving ordering between controls.
struct LatestCommandQueue<Value> {
    private var order: [String] = []
    private var values: [String: Value] = [:]
    var isEmpty: Bool { order.isEmpty }
    func contains(_ key: String) -> Bool { values[key] != nil }
    mutating func put(_ key: String, _ value: Value) {
        if values[key] == nil { order.append(key) }
        values[key] = value
    }
    mutating func pop() -> (String, Value)? {
        guard let key = order.first else { return nil }
        order.removeFirst()
        return values.removeValue(forKey: key).map { (key, $0) }
    }
    mutating func removeAll() { order.removeAll(); values.removeAll() }
}

// One anonymous session spool: unlinked immediately, reclaimed by the OS even after a crash.
// Serial I/O keeps a complete transcript without an ever-growing array or blocking SwiftUI.
final class SessionLog {
    private let queue = DispatchQueue(label:"com.binarybears.xb30.session-log",qos:.utility)
    private let handle: FileHandle?
    private var fallback = Data()
    private let formatter: ISO8601DateFormatter = {
        let f=ISO8601DateFormatter();f.formatOptions=[.withInternetDateTime,.withFractionalSeconds];return f
    }()
    init() {
        var path=Array(FileManager.default.temporaryDirectory.appendingPathComponent("SRS-XB-session.XXXXXX").path.utf8CString)
        let fd=mkstemp(&path)
        if fd >= 0 {
            unlink(path);handle=FileHandle(fileDescriptor:fd,closeOnDealloc:true)
        } else { handle=nil }
    }
    func append(_ line:String) {
        let timestamp=Date()
        queue.async {
            let data=Data((self.formatter.string(from:timestamp)+" "+line+"\n").utf8)
            if let handle=self.handle { handle.write(data) } else { self.fallback.append(data) }
        }
    }
    func snapshot() -> Data {
        queue.sync {
            guard let handle else { return fallback }
            handle.seek(toFileOffset:0);let data=handle.readDataToEndOfFile();handle.seekToEndOfFile();return data
        }
    }
    func export(to url:URL, completion:@escaping (Error?) -> Void) {
        queue.async {
            do {
                if !FileManager.default.fileExists(atPath:url.path) { FileManager.default.createFile(atPath:url.path,contents:nil) }
                let output=try FileHandle(forWritingTo:url);defer { try? output.close() }
                try output.truncate(atOffset:0)
                if let handle=self.handle {
                    try handle.seek(toOffset:0);defer { handle.seekToEndOfFile() }
                    while let chunk=try handle.read(upToCount:65536), !chunk.isEmpty { try output.write(contentsOf:chunk) }
                } else { try output.write(contentsOf:self.fallback) }
                completion(nil)
            } catch { completion(error) }
        }
    }
}

@MainActor final class Controller: ObservableObject {
    @Published var volume = 24
    @Published private(set) var volumeMaximum = 50
    @Published private(set) var volumeAdjusted = false
    private var requestedVolume: Int?
    var volumeHelp: String { volumeAdjusted ? "The speaker limited the requested volume. This is the confirmed level, not a connection error. Available volume can depend on battery charge." : "Volume is sent automatically and checked with the speaker." }
    @Published var autoStandby = true
    @Published var btStandby = false
    @Published var lighting = "LIGHT OFF"
    @Published var preset = "FLAT"
    @Published var bass = 0
    @Published var middle = 0
    @Published var treble = 0
    @Published var codec = "AUTO"
    @Published var clearAudio = false
    @Published private(set) var clearAudioEditable = true
    @Published var battery = "—"
    @Published var firmware = "—"
    private(set) var batteryReadAt: Date?
    private let sessionLog=SessionLog()
    var logLines: [String] { String(decoding:sessionLog.snapshot(),as:UTF8.self).split(separator:"\n").map(String.init) }
    private var logStatusChanges: AnyCancellable?
    let transport = XB30Transport()
    private var transportChanges: AnyCancellable?
    private var observed = XB30SettingsState()
    private var pending = LatestCommandQueue<() -> Void>()
    private var due: [String: Date] = [:]
    private var pump: DispatchWorkItem?
    @Published private(set) var hasPending = false
    @Published private(set) var activeKey: String?

    func enqueue(_ key: String, delay: TimeInterval = 0, action: @escaping () -> Void) {
        guard transport.ready else { return }
        sessionLog.append("INTENT "+key)
        pending.put(key, action); due[key] = Date().addingTimeInterval(delay)
        if !hasPending { hasPending = true }
        scheduleDrain()
    }

    private func group(_ key: String) -> String { key == "soundStatus" || key == "presetStatus" ? "sound" : key }
    private func accepts(_ key: String) -> Bool {
        if let activeKey, group(activeKey) == key { return false }
        if key == "sound" { return !["sound", "soundStatus", "presetStatus"].contains { pending.contains($0) } }
        return !pending.contains(key)
    }
    private func scheduleDrain(after delay:TimeInterval = 0.01) {
        pump?.cancel()
        let work=DispatchWorkItem { [weak self] in self?.drain() };pump=work
        DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:work)
    }
    private func drain() {
        guard transport.ready else {
            pending.removeAll(); due.removeAll(); requestedVolume=nil
            if hasPending { hasPending = false }
            if activeKey != nil { activeKey = nil }
            return
        }
        guard !transport.busy else { return }
        if let finished = activeKey {
            activeKey = nil
            let key = group(finished)
            if accepts(key) { reconcile(key) }
        }
        if let deadline=due.values.max(), deadline > Date() {
            scheduleDrain(after:max(0.01,deadline.timeIntervalSinceNow));return
        }
        guard let (key, action) = pending.pop() else { return }
        due.removeValue(forKey:key); activeKey = key
        if hasPending != !pending.isEmpty { hasPending = !pending.isEmpty }
        action()
        if !transport.busy { scheduleDrain() }
    }
    private func assign<T: Equatable>(_ key: ReferenceWritableKeyPath<Controller,T>, _ value: T?) {
        if let value, self[keyPath:key] != value { self[keyPath:key] = value }
    }
    private func reconcile(_ key: String) {
        switch key {
        case "volume":
            if let requestedVolume, let actual=observed.volume {
                assign(\.volumeAdjusted, actual != requestedVolume);self.requestedVolume=nil
            }
            assign(\.volume, observed.volume)
        case "auto": assign(\.autoStandby, observed.autoStandby)
        case "bt": assign(\.btStandby, observed.btStandby)
        case "codec": if let id=observed.codecID { assign(\.codec, id == 1 ? "SBC" : "AUTO") }
        case "light": if let id=observed.lightingID, (0x10...0x1c).contains(id) { assign(\.lighting, lights[Int(id)-0x10]) }
        case "sound":
            assign(\.clearAudio, observed.clearAudio)
            assign(\.clearAudioEditable, observed.clearAudioEditable)
            if let id=observed.presetID { assign(\.preset, id == 1 ? "EXTRA BASS" : "FLAT") }
            assign(\.bass, observed.bass); assign(\.middle, observed.middle); assign(\.treble, observed.treble)
        default: break
        }
    }
    var checking: Bool { transport.connecting || transport.busy || hasPending || activeKey != nil || (transport.connected && !transport.ready && !transport.failed) }
    var stateLabel: String { transport.failed ? "Connection needs attention" : transport.ready ? "Connected" : (transport.connected || transport.connecting ? "Connecting…" : "Disconnected") }
    var stateColor: Color { transport.failed ? .red : checking ? .yellow : (transport.ready ? .green : .red) }

    let lights = XB30Command.lightNames

    init() {
        sessionLog.append("SESSION START XB30 Controller \(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development") · \(ProcessInfo.processInfo.operatingSystemVersionString)")
        logStatusChanges=transport.$status.removeDuplicates().sink { [weak self] in self?.sessionLog.append("STATE "+$0) }
        // Raw wire logs/status do not invalidate the interface. Only meaningful state transitions do.
        transportChanges = Publishers.CombineLatest(
            Publishers.CombineLatest3(transport.$connected, transport.$ready, transport.$failed),
            Publishers.CombineLatest3(transport.$connecting, transport.$busy, transport.$restoringRadio)
        ).map { [$0.0.0, $0.0.1, $0.0.2, $0.1.0, $0.1.1, $0.1.2] }
            .removeDuplicates().receive(on:DispatchQueue.main).sink { [weak self] _ in self?.objectWillChange.send();self?.scheduleDrain() }
        transport.onFrame = { [weak self] frame in
            Task { @MainActor in self?.apply(frame) }
        }
        transport.onLog = { [log=sessionLog] line in
            if CommandLine.arguments.contains("--debug") { print(line);fflush(stdout) }
            log.append(line)
        }
    }

    private func apply(_ frame: TandemFrame) {
        guard frame.dataType == 0, frame.payload.count >= 3 else { return }
        let p = Array(frame.payload)
        observed.consume(p)
        assign(\.volumeMaximum, observed.volumeMaximum)
        assign(\.firmware, observed.firmware)
        if p[0] == 0xf3, p[1] == 0x12, p[2] == 0x3f, let value=observed.batteryText {
            assign(\.battery, value); batteryReadAt=Date()
        }
        for key in ["volume", "sound", "auto", "bt", "light", "codec"] where accepts(key) { reconcile(key) }
    }

    func exportLog() {
        let panel=NSSavePanel();panel.nameFieldStringValue="SRS-XB-data.log"
        panel.begin { [weak self] response in
            guard let self, response == .OK, let url=panel.url else { return }
            self.sessionLog.append("EXPORT SNAPSHOT firmware=\(self.firmware) battery=\(self.battery) volume=\(self.volume)/\(self.volumeMaximum) preset=\(self.preset) clearAudio=\(self.clearAudio) EQ=\(self.bass),\(self.middle),\(self.treble) light=\(self.lighting) autoStandby=\(self.autoStandby) btStandby=\(self.btStandby) codecPreference=\(self.codec)")
            self.sessionLog.export(to:url) { error in
                guard let error else { return }
                DispatchQueue.main.async { let alert=NSAlert();alert.messageText="Export failed";alert.informativeText=error.localizedDescription;alert.runModal() }
            }
        }
    }

    private func submit(_ key: String, _ payload: [UInt8], query: [UInt8], delay: TimeInterval = 0) {
        enqueue(key, delay: delay) { [weak self] in self?.transport.send(payload, readback: query) }
    }
    func setVolume() { requestedVolume=volume; if volumeAdjusted { volumeAdjusted=false }; submit("volume", XB30Command.volume(volume, maximum:volumeMaximum), query: [0x91, 0x01], delay: 0.16) }
    func setAutoStandby() { submit("auto", XB30Command.autoStandby(autoStandby), query: [0xf2,0x12,0x1f,0xff]) }
    func setBTStandby() { submit("bt", XB30Command.btStandby(btStandby), query: [0xf2,0x12,0x2f,0xff]) }
    func setLight() { if let command = XB30Command.light(named: lighting) { submit("light", command, query: [0xf2,0x11,0x1f,0xff]) } }
    func setPreset() {
        clearAudio = preset == "EXTRA BASS";clearAudioEditable = !clearAudio
        submit("sound", XB30Command.preset(extraBass:clearAudio), query:[0x91,0x10,0x0f,0xff,0])
        enqueue("soundStatus") { [weak self] in self?.transport.send([0x91,0x11,0xff,0xff,0]) }
    }
    func setEQ() { submit("sound", XB30Command.equalizer(bass:bass,middle:middle,treble:treble), query:XB30Command.eqQuery, delay:0.18) }
    func setClearAudio() {
        preset = clearAudio ? "EXTRA BASS" : "FLAT";clearAudioEditable = !clearAudio
        submit("sound", XB30Command.clearAudio(clearAudio), query:[0x91,0x11,0xff,0xff,0])
        enqueue("presetStatus") { [weak self] in self?.transport.send([0x91,0x10,0x0f,0xff,0]) }
    }
    func setCodec() { submit("codec", XB30Command.codec(sbc:codec == "SBC"), query:[0xf2,0x20,0x01,0x0f,0xff]) }

}

struct GlassSurface: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .popover; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

private enum UIStyle {
    static let spacing: CGFloat = 8
    static let radius: CGFloat = 14
}
struct UtilityCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: UIStyle.spacing) { content }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background((scheme == .dark ? Color.white.opacity(0.055) : Color.white.opacity(0.45)), in: RoundedRectangle(cornerRadius:UIStyle.radius))
            .overlay(RoundedRectangle(cornerRadius:UIStyle.radius).strokeBorder(Color.primary.opacity(0.06)))
    }
}
struct HelpBubble: View {
    let title: String
    let text: String
    @State private var shown = false
    var body: some View {
        Button { shown.toggle() } label: { Image(systemName:"questionmark.circle").foregroundStyle(.secondary) }
            .buttonStyle(.plain).accessibilityLabel("About \(title)").help(text)
            .popover(isPresented:$shown) {
                VStack(alignment:.leading,spacing:10) {
                    Text(title).font(.headline)
                    Text(text).font(.system(size:12)).fixedSize(horizontal:false,vertical:true)
                }.padding(18).frame(width:280)
            }
    }
}
enum ControlHelp {
    static let sound = "Extra Bass also enables ClearAudio+ on this speaker; they cannot be controlled independently. Choose Flat to turn both off and use manual EQ."
    static let codec = "Auto prioritizes sound quality and negotiates a supported codec with your audio source. SBC prioritizes connection stability. This is a preference, not a report of the active codec. macOS cannot gain LDAC support through this setting. Changing mode may interrupt audio briefly."
    static let autoStandby = "Turns the speaker off after about 15 minutes without operations or audio, provided no hands-free phone connection is active. Very quiet AUDIO IN input can also count as silence."
    static let btStandby = "Allows an already paired Bluetooth device to wake and connect to the speaker. This works only while the speaker is connected to AC power, not on its built-in battery alone. When the speaker is off, an orange power indicator shows Bluetooth standby."
}
struct LightSwatch: View {
    let index: Int
    static let colors: [[UInt32]] = [[0x657383],[0xaa26ff,0x2455ff,0xff243a,0x35ed65],[0xff384e,0xc04b99,0x933be5],[0x6ddfff,0x56e7a1,0x397dff,0xf3ed98,0xf5fcff],[0xff302c,0xff7733,0xffc25a],[0x245dff,0x58dfff,0xeffaff],[0xf5faff,0xfff0d8],[0xdf59c7],[0x30d9e8],[0xb3e755],[0xe85439],[0xf1f6ff],[0xffd39a]]
    var body: some View {
        let colors=Self.colors[index].map { Color(red:Double(($0 >> 16) & 255)/255,green:Double(($0 >> 8) & 255)/255,blue:Double($0 & 255)/255) }
        RoundedRectangle(cornerRadius:8).fill(LinearGradient(colors:colors,startPoint:.topLeading,endPoint:.bottomTrailing))
            .overlay {
                if index == 0 || [1,2,4,5,6].contains(index) || index == 3 {
                    Image(systemName:index == 0 ? "lightbulb.slash" : [1,2,4,5,6].contains(index) ? "bolt.fill" : "sparkles")
                        .font(.system(size:16,weight:.medium)).foregroundStyle(index == 6 ? Color.black.opacity(0.7) : .white)
                }
            }.overlay(RoundedRectangle(cornerRadius:8).strokeBorder(.white.opacity(0.22)))
    }
}
struct LightingPalette: View {
    @ObservedObject var controller: Controller
    static let names = ["Off","Rave","Chill","No flash","Hot","Cool","Strobe","Magenta","Cyan","Lime","Cinnabar","Daylight","Light bulb"]
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            Text("Lighting palette").font(.headline)
            Text("Choose a mood. ⚡ indicates flashing lights.").font(.system(size:11)).foregroundStyle(.secondary)
            tiles(Array(1...6))
            Divider()
            Text("CALM · SOFT LIGHT").font(.system(size:10,weight:.semibold)).foregroundStyle(.secondary)
            tiles(Array(7...12))
        }.padding(16).frame(width:310).background(.regularMaterial)
    }
    private func tiles(_ indices: [Int]) -> some View {
        LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:3),spacing:8) {
            ForEach(indices,id:\.self) { index in
                Button {
                    controller.lighting=controller.lights[index];controller.setLight()
                } label: {
                    VStack(spacing:5) {
                        LightSwatch(index:index).frame(height:28)
                        HStack(spacing:3) {
                            Text(Self.names[index]).lineLimit(1)
                            if controller.lighting == controller.lights[index] { Image(systemName:"checkmark").fontWeight(.bold) }
                        }.font(.system(size:10,weight:.medium)).frame(height:13)
                    }.padding(6).frame(maxWidth:.infinity)
                        .background(Color.primary.opacity(controller.lighting == controller.lights[index] ? 0.1 : 0.035),in:RoundedRectangle(cornerRadius:12))
                        .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(controller.lighting == controller.lights[index] ? Color.accentColor : Color.primary.opacity(0.06),lineWidth:1.5))
                }.buttonStyle(.plain).disabled(!controller.transport.ready)
                    .accessibilityLabel(controller.lights[index].capitalized)
                    .help(index == 3 ? "Random colors without flash" : index >= 7 ? "Soft \(Self.names[index].lowercased()) illumination" : controller.lights[index].capitalized)
            }
        }
    }
}
struct AboutView: View {
    @ObservedObject var controller: Controller
    var body: some View {
        VStack(spacing:18) {
            Image(nsImage:AppIcon.bear).resizable().scaledToFit().frame(width:76,height:76)
            VStack(spacing:5) {
                Text("XB30 Controller").font(.system(size:24,weight:.bold))
                Text("from BinaryBears").font(.system(size:14,weight:.medium))
                Link("binarybears.com ↗",destination:URL(string:"https://binarybears.com")!)
            }
            Grid(alignment:.leading,horizontalSpacing:28,verticalSpacing:12) {
                info("App version",Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Development")
                info("Device","SRS-XB30")
                info("Firmware",controller.transport.ready ? controller.firmware : "Connect to read")
                info("Battery",controller.transport.ready ? controller.battery : "Connect to read")
                info("Connection",controller.stateLabel)
                info("Compatibility","macOS 13 or later")
            }.font(.system(size:12)).padding(18).frame(maxWidth:.infinity).background(.quaternary.opacity(0.35),in:RoundedRectangle(cornerRadius:14))
            Text("Independent project. Not affiliated with Sony.\nBattery level is approximate; charging status and the active audio codec are not reported by the control protocol.")
                .font(.system(size:11)).foregroundStyle(.secondary).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
        }.padding(26).frame(width:360).background(.regularMaterial)
    }
    private func info(_ label: String, _ value: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary);Text(value).textSelection(.enabled) }
    }
}
@MainActor final class AboutWindow {
    static let shared = AboutWindow()
    private var window: NSWindow?
    func show(_ controller: Controller) {
        if window == nil {
            let hosting=NSHostingView(rootView:AboutView(controller:controller))
            let panel=NSWindow(contentRect:NSRect(origin:.zero,size:hosting.fittingSize),styleMask:[.titled,.closable],backing:.buffered,defer:false)
            panel.title="About XB30 Controller";panel.contentView=hosting;panel.isReleasedWhenClosed=false
            panel.center();window=panel
        }
        window?.makeKeyAndOrderFront(nil);NSApp.activate(ignoringOtherApps:true)
    }
}

enum BatteryLevel {
    static func fraction(_ text:String) -> Double? {
        if text.trimmingCharacters(in:.whitespacesAndNewlines).lowercased() == "fully charged" { return 1 }
        guard text.contains("%"), let number=text.split(whereSeparator:{ !$0.isNumber }).first, let value=Double(number), (0...100).contains(value) else { return nil }
        return value/100
    }
}
struct BatteryGauge: View {
    let level:Double?
    private var fill:Color { guard let level else { return .secondary };return level <= 0.2 ? .orange : .green }
    var body: some View {
        HStack(spacing:1) {
            GeometryReader { geometry in
                RoundedRectangle(cornerRadius:3).strokeBorder(Color.secondary,lineWidth:1.5)
                if let level, level > 0 {
                    RoundedRectangle(cornerRadius:1.5).fill(fill)
                        .frame(width:max(0,(geometry.size.width-6)*level),height:geometry.size.height-6).offset(x:3,y:3)
                }
            }
            RoundedRectangle(cornerRadius:1).fill(Color.secondary).frame(width:2,height:6)
        }.frame(width:30,height:17).accessibilityHidden(true)
    }
}
struct ContentView: View {
    @ObservedObject var controller: Controller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var showEQ = false
    @State private var showPalette = false
    @State private var confirmRadioReset = false
    @State private var lastLight = "RAVE"
    init(controller: Controller, eqExpanded: Bool = false, detailsExpanded: Bool = false) {
        self.controller=controller;_showEQ=State(initialValue:eqExpanded)
    }
    private var ready: Bool { controller.transport.ready }
    private func binding<T>(_ key: ReferenceWritableKeyPath<Controller, T>, action: @escaping () -> Void) -> Binding<T> {
        Binding(get: { controller[keyPath:key] }, set: { controller[keyPath:key] = $0; action() })
    }
    private func title(_ text: String, _ symbol: String) -> some View {
        Label(text,systemImage:symbol).font(.system(size:14,weight:.semibold)).labelStyle(.titleAndIcon)
    }
    private func band(_ name: String, _ key: ReferenceWritableKeyPath<Controller, Int>) -> some View {
        HStack {
            Text(name).frame(width:43,alignment:.leading)
            Slider(value:Binding(get:{Double(controller[keyPath:key])},set:{controller[keyPath:key]=Int($0);controller.setEQ()}),in:-10...10,step:1)
                .accessibilityLabel(name).help("Adjust \(name.lowercased()) from −10 to +10. Select Flat to use manual EQ.")
            Text(ready ? String(format:"%+d",controller[keyPath:key]) : "—").monospacedDigit().frame(width:27,alignment:.trailing)
        }.font(.system(size:12))
    }
    private var header: some View {
        HStack(spacing:10) {
            Image(nsImage:AppIcon.speaker).resizable().scaledToFit().frame(width:106,height:78).accessibilityLabel("BinaryBears speaker preview")
            VStack(alignment:.leading,spacing:9) {
                HStack {
                    Text("XB30 Controller").font(.system(size:17,weight:.bold)).lineLimit(1)
                    Button { AboutWindow.shared.show(controller) } label: { Image(systemName:"info.circle").foregroundStyle(.secondary) }
                        .buttonStyle(.plain).help("About XB30 Controller").accessibilityLabel("About XB30 Controller")
                    Spacer(minLength:0)
                }
                HStack {
                    Button(controller.transport.connecting ? "Cancel" : controller.transport.connected ? "Disconnect" : "Connect") {
                        if controller.transport.connected || controller.transport.connecting { controller.transport.disconnect() }
                        else { controller.transport.connect(reconnectAudio:true) }
                    }.controlSize(.small).disabled(controller.transport.restoringRadio)
                        .help("Connect to the paired speaker and read its settings. Reconnecting can briefly interrupt audio.")
                    Spacer(minLength:4)
                    Image(systemName:controller.transport.failed ? "exclamationmark.circle.fill" : controller.checking ? "clock.fill" : ready ? "checkmark.circle.fill" : "circle.fill")
                        .foregroundStyle(controller.stateColor)
                    Text(controller.stateLabel).font(.system(size:11)).lineLimit(1)
                }.help(controller.transport.status).accessibilityElement(children:.combine)
                HStack(spacing:10) {
                    Image(systemName:"speaker.wave.2.fill").foregroundStyle(.secondary)
                    Slider(value:Binding(get:{Double(controller.volume)},set:{controller.volume=Int($0.rounded());controller.setVolume()}),in:0...Double(controller.volumeMaximum))
                        .disabled(!ready).accessibilityLabel("Volume").help("Speaker volume. Changes apply automatically. The speaker may limit its maximum output; the confirmed level is always shown.")
                    Text(ready ? "\(Int((Double(controller.volume)/Double(controller.volumeMaximum)*100).rounded()))%" : "—").monospacedDigit().frame(width:36,alignment:.trailing).foregroundStyle(controller.volumeAdjusted ? Color.orange : Color.primary).help(controller.volumeHelp)
                }
            }
        }
    }
    private var statusStrip: some View {
        UtilityCard {
            HStack(spacing:0) {
                HStack(spacing:10) {
                    BatteryGauge(level:ready ? BatteryLevel.fraction(controller.battery) : nil)
                    VStack(alignment:.leading,spacing:3) {
                        Text("Battery").fontWeight(.medium)
                        Text(ready ? controller.battery : "—").foregroundStyle(.secondary)
                    }.frame(width:112,alignment:.leading)
                }.frame(maxWidth:.infinity).help("Approximate level reported by the speaker. The fill follows that estimate; it does not indicate charging.")
                Divider().frame(height:32)
                HStack(spacing:10) {
                    Image(systemName:"antenna.radiowaves.left.and.right").font(.system(size:20)).foregroundStyle(.blue).frame(width:30,height:22)
                    VStack(alignment:.leading,spacing:3) {
                        Text("Bluetooth").fontWeight(.medium)
                        Text(ready ? "Preference: \(controller.codec == "SBC" ? "SBC" : "Auto")" : "Not connected").foregroundStyle(.secondary)
                    }.frame(width:112,alignment:.leading)
                }.frame(maxWidth:.infinity).help("Auto / SBC is the speaker preference. The control protocol does not report the currently negotiated audio codec.")
            }.font(.system(size:12))
        }
    }
    private var sound: some View {
        UtilityCard {
            HStack { title("Sound","waveform");Spacer();HelpBubble(title:"Extra Bass & ClearAudio+",text:ControlHelp.sound) }
            Text("Sound preset").font(.system(size:12,weight:.medium)).foregroundStyle(.secondary)
            Picker("Sound preset",selection:binding(\.preset,action:controller.setPreset)) {
                Text("Flat").tag("FLAT");Text("Extra Bass").tag("EXTRA BASS")
            }.labelsHidden().pickerStyle(.segmented).disabled(!ready)
                .help(ControlHelp.sound)
            Divider().padding(.vertical,3)
            HStack {
                VStack(alignment:.leading,spacing:5) {
                    Text("Equalizer").fontWeight(.medium)
                    Text(ready ? "Bass \(controller.bass > 0 ? "+" : "")\(controller.bass)   Mid \(controller.middle > 0 ? "+" : "")\(controller.middle)   Treble \(controller.treble > 0 ? "+" : "")\(controller.treble)" : "Bass —   Mid —   Treble —")
                        .font(.system(size:11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.85)
                }
                Spacer(minLength:5)
                Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.18)) { showEQ.toggle() } } label: {
                    Image(systemName:showEQ ? "chevron.up" : "chevron.down")
                }.accessibilityLabel(showEQ ? "Close EQ" : "Open EQ").help("Show or hide the equalizer without changing its values.")
            }
            Spacer(minLength:0)
        }.frame(height:190)
    }
    private var lighting: some View {
        UtilityCard {
            HStack {
                title("Lighting","lightbulb")
                Spacer()
                Toggle("Lighting",isOn:Binding(get:{controller.lighting != "LIGHT OFF"},set:{ on in
                    if !on { lastLight=controller.lighting }
                    controller.lighting=on ? lastLight : "LIGHT OFF";controller.setLight()
                })).labelsHidden().toggleStyle(.switch).disabled(!ready).help("Turn illumination on or restore the last selected mode.")
            }
            Button { showPalette.toggle() } label: {
                HStack(spacing:8) {
                    LightSwatch(index:controller.lights.firstIndex(of:controller.lighting) ?? 0).frame(width:32,height:28)
                    Text(controller.lighting == "RANDOM FLASH OFF" ? "No flash" : controller.lighting.capitalized).font(.system(size:11,weight:.medium)).lineLimit(1)
                    Spacer(minLength:0);Image(systemName:"chevron.down").font(.system(size:9,weight:.semibold))
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(!ready).help("Open the lighting palette")
                .popover(isPresented:$showPalette) { LightingPalette(controller:controller) }
            Spacer(minLength:0)
        }.frame(height:100)
    }
    private var bluetooth: some View {
        UtilityCard {
            HStack { Text("Bluetooth Mode").font(.system(size:13,weight:.semibold));Spacer(minLength:0);HelpBubble(title:"Bluetooth audio mode",text:ControlHelp.codec) }
            Picker("Bluetooth mode",selection:binding(\.codec,action:controller.setCodec)) {
                Text("Auto").tag("AUTO");Text("SBC").tag("SBC")
            }.labelsHidden().pickerStyle(.segmented).disabled(!ready)
                .help(ControlHelp.codec)
            Spacer(minLength:0)
        }.frame(height:82)
    }
    private var settings: some View {
        UtilityCard {
            HStack {
                title("Device Settings","gearshape")
                Spacer()
                Menu {
                    Button("Export log…",action:controller.exportLog)
                    Button("Bluetooth Settings…") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.BluetoothSettings")!) }
                    Button("Restart Bluetooth…") { confirmRadioReset=true }
                    Divider()
                    Button("About XB30 Controller") { AboutWindow.shared.show(controller) }
                    Button("Quit XB30 Controller") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q")
                } label: { Image(systemName:"ellipsis.circle") }.menuStyle(.borderlessButton).frame(width:25).help("App information, logs, Bluetooth recovery and Quit")
            }
            HStack(spacing:12) {
                HStack(spacing:5) {
                    Toggle("Auto standby",isOn:binding(\.autoStandby,action:controller.setAutoStandby)).disabled(!ready).help(ControlHelp.autoStandby)
                    HelpBubble(title:"Auto standby",text:ControlHelp.autoStandby)
                }.frame(maxWidth:.infinity,alignment:.leading)
                HStack(spacing:5) {
                    Toggle("Bluetooth standby",isOn:binding(\.btStandby,action:controller.setBTStandby)).disabled(!ready).help(ControlHelp.btStandby)
                    HelpBubble(title:"Bluetooth standby",text:ControlHelp.btStandby)
                }.frame(maxWidth:.infinity,alignment:.leading)
            }.toggleStyle(.switch)

        }
    }

    var body: some View {
        VStack(spacing:UIStyle.spacing) {
                header;statusStrip
                HStack(alignment:.top,spacing:UIStyle.spacing) {
                    sound.frame(maxWidth:.infinity)
                    VStack(spacing:UIStyle.spacing) { lighting;bluetooth }.frame(maxWidth:.infinity)
                }
                if showEQ {
                    UtilityCard {
                        HStack { title("Equalizer","slider.horizontal.3");Spacer();Button("Close") { showEQ=false } }
                        VStack(spacing:9) { band("Bass",\.bass);band("Mid",\.middle);band("Treble",\.treble) }.disabled(!ready || controller.clearAudio)
                        if controller.clearAudio { Text("Select Flat to adjust EQ.").font(.system(size:11)).foregroundStyle(.secondary) }
                    }
                }
                settings
        }.padding(12).frame(width:440).fixedSize(horizontal:false,vertical:true)
            .background { if reduceTransparency { Color(nsColor:.windowBackgroundColor) } else { GlassSurface() } }
            .tint(.blue).font(.system(size:12)).controlSize(.small)
            .alert("Restart Bluetooth on this Mac?",isPresented:$confirmRadioReset) {
                Button("Cancel",role:.cancel) {};Button("Restart Bluetooth",role:.destructive,action:controller.transport.restoreBluetooth)
            } message: { Text("All Bluetooth accessories will disconnect briefly.") }
    }
}

enum AppIcon {
    static let bear: NSImage = { NSImage(contentsOfFile:Bundle.main.path(forResource:"BinaryBearsMark",ofType:"png") ?? "") ?? full }()
    static let speaker: NSImage = { NSImage(contentsOfFile:Bundle.main.path(forResource:"SpeakerPreview",ofType:"png") ?? "") ?? full }()
    static let full: NSImage = { NSImage(contentsOfFile:Bundle.main.path(forResource:"AppIcon",ofType:"png") ?? "") ?? NSImage(systemSymbolName:"hifispeaker.fill",accessibilityDescription:"XB30")! }()
    static let menu: NSImage = {
        let image = NSImage(contentsOfFile:Bundle.main.path(forResource:"MenuBarTemplate",ofType:"pdf") ?? "") ?? NSImage(systemSymbolName:"hifispeaker.fill",accessibilityDescription:"XB30")!
        image.isTemplate = true; image.size = NSSize(width:26,height:18)
        return image
    }()
}

#if !TESTING
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private let controller = Controller()
    private var profileReady: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) { start() }
    func start() {
        guard statusItem == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: 36)
        if let button = statusItem.button {
            button.image = AppIcon.menu
            button.toolTip = "XB30 Controller"
            button.setAccessibilityLabel("XB30 Controller")
            button.sendAction(on:[.leftMouseUp,.rightMouseUp])
            button.target = self; button.action = #selector(statusItemClicked)
        }
        popover.behavior = .transient
        let hosting = NSHostingController(rootView:ContentView(controller:controller))
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        hosting.view.layoutSubtreeIfNeeded()
        popover.contentSize = hosting.view.fittingSize
        if CommandLine.arguments.contains("--show") { DispatchQueue.main.async { self.togglePopover() } }
        if CommandLine.arguments.contains("--debug") && CommandLine.arguments.contains("--profile") {
            profileReady=controller.transport.$ready.filter { $0 }.first().receive(on:DispatchQueue.main).sink { [weak self] _ in
                self?.profile()
            }
        }
        // Explicit local diagnostics only; ordinary launch never connects or resets the radio.
        if CommandLine.arguments.contains("--debug") {
            DispatchQueue.main.async {
                if CommandLine.arguments.contains("--recover-radio") { self.controller.transport.restoreBluetooth() }
                else if CommandLine.arguments.contains("--connect") { self.controller.transport.connect(reconnectAudio:true) }
            }
        }
    }
    // Explicit development instrumentation: same live views/controller, no simulated Bluetooth state.
    private func profile() {
        let baseline=controller.lighting
        func mark(_ name:String) { print("PROFILE "+name);fflush(stdout) }
        popover.performClose(nil);mark("hidden")
        DispatchQueue.main.asyncAfter(deadline:.now()+20) { self.togglePopover();mark("visible") }
        DispatchQueue.main.asyncAfter(deadline:.now()+40) {
            mark("edits")
            for i in 0..<24 {
                DispatchQueue.main.asyncAfter(deadline:.now()+Double(i)*0.5) {
                    self.controller.lighting=i % 2 == 0 ? "CALM CYAN" : "CALM MAGENTA";self.controller.setLight()
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+55) { self.controller.lighting=baseline;self.controller.setLight();mark("restored") }
        DispatchQueue.main.asyncAfter(deadline:.now()+65) { mark("complete") }
    }
    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.performClose(nil)
            let menu=NSMenu()
            let quit=NSMenuItem(title:"Quit XB30 Controller",action:#selector(quitApp),keyEquivalent:"q")
            quit.target=self;menu.addItem(quit)
            statusItem.menu=menu
            statusItem.button?.performClick(nil)
            statusItem.menu=nil
        } else { togglePopover() }
    }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { popover.show(relativeTo:button.bounds,of:button,preferredEdge:.minY); NSApp.activate(ignoringOtherApps:true) }
    }
    func applicationWillTerminate(_ notification: Notification) { controller.transport.disconnect() }
}
@main struct XB30ControlApp {
    @MainActor static let delegate = AppDelegate()
    @MainActor static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        delegate.start()
        app.run()
    }
}
#endif

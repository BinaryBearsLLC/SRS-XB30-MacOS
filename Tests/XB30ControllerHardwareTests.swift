import Foundation

// Runs the same controller and command queue used by the popover, on real hardware.
@main @MainActor struct XB30ControllerHardwareTests {
    static func pump(_ seconds: Double) { RunLoop.main.run(until:Date().addingTimeInterval(seconds)) }
    static func main() {
        setbuf(stdout,nil)
        let c=Controller()
        c.transport.restoreBluetooth()
        let deadline=Date().addingTimeInterval(45)
        var longestPump=0.0
        while !c.transport.ready && Date()<deadline { let before=Date();pump(0.05);longestPump=max(longestPump,Date().timeIntervalSince(before)) }
        guard c.transport.ready else { print("FAIL CONNECT \(c.transport.status)");exit(1) }
        pump(0.3)
        let baseline=(c.volume,c.autoStandby,c.btStandby,c.lighting,c.preset,c.clearAudio,c.bass,c.middle,c.treble,c.codec)
        print("BASELINE volume=\(c.volume) light=\(c.lighting) sound=\(c.preset) clear=\(c.clearAudio) EQ=\(c.bass),\(c.middle),\(c.treble) codec=\(c.codec)")
        var failures=0
        func settle()->Bool {
            let limit=Date().addingTimeInterval(12)
            repeat { pump(0.1) } while c.transport.ready && (c.checking || c.activeKey != nil) && Date()<limit
            pump(0.2)
            return c.transport.ready && !c.checking
        }
        func check(_ label:String,_ condition:Bool) { print("\(condition ? "PASS" : "FAIL") \(label)");if !condition { failures+=1 } }
        func observedSince(_ index:Int)->XB30SettingsState {
            var state=XB30SettingsState()
            for line in c.logLines.dropFirst(index) {
                guard let range=line.range(of:" RX ") else { continue }
                let hex=String(line[range.upperBound...]);if hex=="ACK" { continue }
                let chars=Array(hex);var bytes:[UInt8]=[]
                for i in stride(from:0,to:chars.count-1,by:2) { if let b=UInt8(String(chars[i...i+1]),radix:16) { bytes.append(b) } }
                state.consume(bytes)
            }
            return state
        }
        check("main run loop stays responsive during connect (max \(longestPump)s)",longestPump<0.5)
        var start=c.logLines.count
        for value in 1...22 { c.volume=value;c.setVolume() }
        check("rapid slider settles",settle())
        check("last volume confirmed by device",observedSince(start).volume==22)
        check("22 slider edits coalesce to one write",c.logLines.dropFirst(start).filter{$0.contains(" TX 9301")}.count==1)
        start=c.logLines.count
        c.autoStandby = !baseline.1;c.setAutoStandby()
        c.btStandby = !baseline.2;c.setBTStandby()
        c.lighting="CALM CYAN";c.setLight()
        check("different controls settle",settle())
        let read=observedSince(start)
        check("standby and light readbacks",read.autoStandby == !baseline.1 && read.btStandby == !baseline.2 && read.lightingID==0x18)
        start=c.logLines.count
        c.clearAudio=false;c.setClearAudio();check("ClearAudio off",settle())
        c.bass=2;c.middle = -1;c.treble=1;c.setEQ();check("EQ settles",settle())
        let eq=observedSince(start);check("three EQ values confirmed",eq.bass==2 && eq.middle == -1 && eq.treble==1)
        c.volume=baseline.0;c.setVolume();c.autoStandby=baseline.1;c.setAutoStandby();c.btStandby=baseline.2;c.setBTStandby();c.lighting=baseline.3;c.setLight();check("restore volume standby lights",settle())
        c.bass=baseline.6;c.middle=baseline.7;c.treble=baseline.8;c.setEQ();check("restore EQ",settle())
        c.preset=baseline.4;c.setPreset();check("restore preset",settle())
        if baseline.5 { c.clearAudio=true;c.setClearAudio();check("restore ClearAudio",settle()) }
        // A pending edit must be discarded across disconnect/reconnect.
        start=c.logLines.count;c.volume=1;c.setVolume();c.transport.disconnect();pump(0.3)
        check("disconnect clears pending edit",!c.hasPending && !c.logLines.dropFirst(start).contains{$0.contains(" TX 9301")})
        c.transport.connect(reconnectAudio:true)
        let reconnect=Date().addingTimeInterval(35)
        while !c.transport.ready && Date()<reconnect { pump(0.05) }
        pump(0.3)
        check("reconnect reuses listener and reads state",c.transport.ready && c.volume==baseline.0 && c.autoStandby==baseline.1 && c.btStandby==baseline.2 && c.lighting==baseline.3)
        print("FINAL \(failures) failures; \(c.stateLabel)")
        try? c.logLines.joined(separator:"\n").write(toFile:".work/controller-hardware-frames.log",atomically:true,encoding:.utf8)
        c.transport.disconnect();exit(failures==0 ? 0:2)
    }
}

import Foundation
import IOBluetooth

@main struct XB30HardwareTests {
    static func pump(_ seconds:Double) { RunLoop.current.run(until:Date().addingTimeInterval(seconds)) }
    static func main() {
        setbuf(stdout,nil)
        let transport = XB30Transport()
        var state = XB30SettingsState()
        transport.onLog = { print(ISO8601DateFormatter().string(from:Date()) + " " + $0) }
        transport.onFrame = { if $0.dataType == 0 { state.consume(Array($0.payload)) } }
        if CommandLine.arguments.contains("--recover-radio") { transport.restoreBluetooth() }
        else { transport.connect(reconnectAudio: true) }
        let limit=Date().addingTimeInterval(45)
        while !transport.ready && Date()<limit { pump(0.1) }
        guard transport.ready, let volume=state.volume, let auto=state.autoStandby, let bt=state.btStandby,
              let light=state.lightingID, let preset=state.presetID, let clear=state.clearAudio,
              let bass=state.bass, let mid=state.middle, let treble=state.treble,
              let codec=state.codecID, let battery=state.batteryText else {
            print("FAIL_INITIAL \(transport.status) STATE \(state)"); transport.disconnect(); exit(1)
        }
        print("BASELINE \(state)")
        if !CommandLine.arguments.contains("--exercise") { print("PASS_ALL_READS BATTERY=\(battery)"); transport.disconnect(); exit(0) }
        var count=0
        var failed=false
        func step(_ name:String,_ payload:[UInt8],_ notification:UInt8?,_ query:[UInt8],_ verify:()->Bool)->Bool {
            transport.send(payload,notification:notification,readback:payload == query ? nil : query,readbackResponse:query[0] == 0x91 ? 0x92 : 0xf3)
            let deadline=Date().addingTimeInterval(10)
            while transport.busy && transport.ready && Date()<deadline { pump(0.05) }
            let ok=transport.ready && !transport.busy && verify()
            print("\(ok ? "PASS" : "FAIL") \(name) STATUS=\(transport.status) STATE=\(state)")
            if ok { count += 1 } else { failed=true }; return ok
        }
        func restore() {
            guard transport.ready else { print("RESTORE_REQUIRED: reference state printed in BASELINE"); return }
            _=step("restore lights",XB30Command.light(named:XB30Command.lightNames[Int(light)-0x10])!,0xf5,[0xf2,0x11,0x1f,0xff]){state.lightingID==light}
            _=step("restore volume",XB30Command.volume(volume),0x94,[0x91,0x01]){state.volume==volume}
            _=step("restore auto standby",XB30Command.autoStandby(auto),0xf5,[0xf2,0x12,0x1f,0xff]){state.autoStandby==auto}
            _=step("restore bt standby",XB30Command.btStandby(bt),0xf5,[0xf2,0x12,0x2f,0xff]){state.btStandby==bt}
            _=step("restore EQ",XB30Command.equalizer(bass:bass,middle:mid,treble:treble),0x92,XB30Command.eqQuery){state.bass==bass && state.middle==mid && state.treble==treble}
            if preset != 0x10 { _=step("restore preset",XB30Command.preset(extraBass:preset==1),0x92,[0x91,0x10,0x0f,0xff,0]){state.presetID==preset} }
            if clear { _=step("restore ClearAudio",XB30Command.clearAudio(true),0x92,[0x91,0x11,0xff,0xff,0]){state.clearAudio==true} }
            _=step("restore codec",XB30Command.codec(sbc:codec==1),nil,[0xf2,0x20,1,0x0f,0xff]){state.codecID==codec}
        }
        func require(_ ok:Bool) { if !ok { restore(); transport.disconnect(); exit(2) } }
        let v=min(volume+1,32)
        require(step("volume",XB30Command.volume(v),0x94,[0x91,1]){state.volume==v})
        require(step("volume zero",XB30Command.volume(0),nil,[0x91,1]){state.volume==0})
        require(step("volume maximum readback",XB30Command.volume(50),nil,[0x91,1]){state.volume != nil && (0...50).contains(state.volume!)})
        print("MAXIMUM requested=50 actual=\(state.volume ?? -1) capability=\(state.volumeMaximum ?? -1)")
        pump(0.8)
        require(step("volume settled query",[0x91,1],nil,[0x91,1]){state.volume != nil})
        print("MAXIMUM settled=\(state.volume ?? -1)")
        require(step("restore volume after extremes",XB30Command.volume(volume),nil,[0x91,1]){state.volume==volume})
        for value in [false,true] {
            require(step("auto standby \(value)",XB30Command.autoStandby(value),0xf5,[0xf2,0x12,0x1f,0xff]){state.autoStandby==value})
            require(step("BT standby \(value)",XB30Command.btStandby(value),0xf5,[0xf2,0x12,0x2f,0xff]){state.btStandby==value})
        }
        for (i,name) in XB30Command.lightNames.enumerated() {
            require(step("light \(name)",XB30Command.light(named:name)!,0xf5,[0xf2,0x11,0x1f,0xff]){state.lightingID==UInt8(0x10+i)})
        }
        require(step("ClearAudio ON",XB30Command.clearAudio(true),0x92,[0x91,0x11,0xff,0xff,0]){state.clearAudio==true})
        require(step("ClearAudio OFF via FLAT",XB30Command.clearAudio(false),0x92,[0x91,0x11,0xff,0xff,0]){state.clearAudio==false})
        for extra in [true,false] { require(step("preset \(extra)",XB30Command.preset(extraBass:extra),0x92,[0x91,0x10,0x0f,0xff,0]){state.presetID==(extra ? 1:0)}) }
        for band in 0..<3 { for value in [-10,0,10] {
            var values=[0,0,0];values[band]=value
            require(step("EQ band \(band) = \(value)",XB30Command.equalizer(bass:values[0],middle:values[1],treble:values[2]),0x92,XB30Command.eqQuery){state.bass==values[0] && state.middle==values[1] && state.treble==values[2]})
        }}
        for sbc in [true,false] { require(step("codec SBC=\(sbc)",XB30Command.codec(sbc:sbc),nil,[0xf2,0x20,1,0x0f,0xff]){state.codecID==(sbc ? 1:0)}) }
        restore()
        guard !failed, state.volume==volume, state.autoStandby==auto, state.btStandby==bt,
              state.lightingID==light, state.presetID==preset, state.clearAudio==clear,
              state.bass==bass, state.middle==mid, state.treble==treble, state.codecID==codec else {
            print("FAIL_FINAL_RESTORE \(state)");transport.disconnect();exit(3)
        }
        print("COMPLETE \(count) verified operations; BATTERY=\(state.batteryText ?? "unknown")")
        transport.disconnect()
    }
}

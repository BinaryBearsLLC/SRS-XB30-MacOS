import Foundation
import Combine

// No radio traffic. Reproduce stale responses during in-flight and pending edits.
@main @MainActor struct ControllerRegression {
    static func pump(_ seconds: Double) { RunLoop.main.run(until:Date().addingTimeInterval(seconds)) }
    static func main() {
        let c=Controller();c.transport.reviewState(connected:true);pump(0.2)
        var updates=0
        let subscription=c.objectWillChange.sink { updates += 1 }
        pump(1);precondition(updates == 0,"Idle UI must not redraw at the queue timer frequency")
        c.transport.reviewStatus("Raw transport progress");pump(0.1)
        precondition(updates == 0,"Wire status must not invalidate the interface")
        func frame(_ p:[UInt8]) { c.transport.onFrame?(TandemFrame(dataType:0,sequence:0,payload:Data(p)));pump(0.04) }
        c.volume=40;c.enqueue("volume") { c.transport.reviewBusy(true) };pump(0.12)
        precondition(c.activeKey == "volume")
        frame([0x92,1,5]);precondition(c.volume == 40,"In-flight edit must win over an old reply")
        c.volume=45;c.enqueue("volume") { c.transport.reviewBusy(true) }
        c.transport.reviewBusy(false);pump(0.12)
        frame([0x92,1,40]);precondition(c.volume == 45,"Latest intent must survive previous command readback")
        frame([0x92,1,45]);c.transport.reviewBusy(false);pump(0.12)
        precondition(c.volume == 45 && c.activeKey == nil && !c.checking)
        frame([0x94,1,30]);precondition(c.volume == 30,"Physical speaker changes must still update idle UI")
        updates=0;frame([0x94,1,30]);precondition(updates == 0,"Identical device reports must not redraw UI")
        c.volume=50;c.setVolume();c.enqueue("volume") { c.transport.reviewBusy(true) };pump(0.12)
        frame([0x92,1,46]);precondition(c.volume == 50)
        c.transport.reviewBusy(false);pump(0.12)
        precondition(c.volume == 46 && c.volumeAdjusted,"A device limit must be reported truthfully after verification")
        c.volume=50;c.setVolume();c.enqueue("volume") { c.transport.reviewBusy(true) };pump(0.12)
        frame([0x92,1,50]);c.transport.reviewBusy(false);pump(0.12)
        precondition(c.volume == 50 && !c.volumeAdjusted,"A confirmed full-charge maximum must display 100% without a limit warning")
        func battery(_ text:String) { frame([0xf3,0x12,0x3f,0xff,0,1,0x21,UInt8(text.utf8.count)]+Array(text.utf8)) }
        battery("About 70%");precondition(c.battery == "About 70%" && BatteryLevel.fraction(c.battery) == 0.7)
        battery("Fully charged");precondition(c.battery == "Fully charged" && BatteryLevel.fraction(c.battery) == 1,"Unsolicited full-battery notification must update immediately")
        precondition(BatteryLevel.fraction("About 20%") == 0.2 && BatteryLevel.fraction("—") == nil && BatteryLevel.fraction("Please charge") == nil)
        // Sound-group readbacks share protection with the initiating write.
        c.preset="EXTRA BASS";c.clearAudio=true
        c.enqueue("sound") { c.transport.reviewBusy(true) };pump(0.12)
        c.enqueue("soundStatus") { c.transport.reviewBusy(true) }
        frame([0x92,0x10,0,0xff,0,0]);precondition(c.preset == "EXTRA BASS")
        c.transport.reviewBusy(false);pump(0.12)
        frame([0x92,0x10,1,0xff,0,0]);frame([0x92,0x11,0xff,0xff,0,0,1,1,1,1])
        c.transport.reviewBusy(false);pump(0.12)
        precondition(c.preset == "EXTRA BASS" && c.clearAudio && !c.clearAudioEditable && !c.checking)
        // Inspect optimistic coupling before the queue is allowed to transmit.
        c.clearAudio=false;c.setClearAudio();precondition(c.preset == "FLAT" && !c.clearAudio)
        c.preset="EXTRA BASS";c.setPreset();precondition(c.clearAudio)
        c.transport.disconnect();pump(0.12)
        precondition(!c.hasPending && c.activeKey == nil)
        withExtendedLifetime(subscription) {}
        print("Controller regression: idle redraw, stale replies, latest intent, external changes, linked sound and disconnect PASS")
    }
}

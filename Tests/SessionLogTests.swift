import Foundation
@main struct SessionLogTests {
 static func main() throws {
    let root=FileManager.default.temporaryDirectory
    func spools() throws -> Set<String> { Set(try FileManager.default.contentsOfDirectory(atPath:root.path).filter{$0.hasPrefix("SRS-XB-session.")}) }
    let before=try spools()
    let log=SessionLog()
    for i in 0..<12000 { log.append("ENTRY \(i)") }
    let data=log.snapshot(),text=String(decoding:data,as:UTF8.self)
    precondition(text.split(separator:"\n").count == 12000 && text.contains("ENTRY 0\n") && text.contains("ENTRY 11999\n"))
    let after=try spools();precondition(after == before,"The temporary spool must have no visible filename")
    let output=root.appendingPathComponent("SRS-XB-log-test-\(UUID().uuidString).log")
    defer { try? FileManager.default.removeItem(at:output) }
    let done=DispatchSemaphore(value:0);var exportError:Error?
    log.export(to:output){ exportError=$0;done.signal() }
    precondition(done.wait(timeout:.now()+5) == .success && exportError == nil)
    let exported=try Data(contentsOf:output);precondition(exported == data,"Export must contain the entire session")
    print("Session log: 12,000 entries retained, exact export, no temporary filename PASS")
 }
}

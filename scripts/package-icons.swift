import AppKit
let root = CommandLine.arguments[1]
let menu = NSImage(contentsOfFile:root+"/MenuBarTemplate.png")!
let view = NSImageView(frame:NSRect(x:0,y:0,width:30,height:20)); view.image = menu
try view.dataWithPDF(inside:view.bounds).write(to:URL(fileURLWithPath:root+"/MenuBarTemplate.pdf"))
let source = NSImage(contentsOfFile:root+"/AppIcon.png")!
let image = NSImage(size:NSSize(width:1024,height:1024))
image.lockFocus()
let bg = NSBezierPath(roundedRect:NSRect(x:22,y:22,width:980,height:980),xRadius:210,yRadius:210)
NSColor.white.setFill(); bg.fill()
source.draw(in:NSRect(x:80,y:215,width:864,height:603))
image.unlockFocus()
let png=NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
try png.write(to:URL(fileURLWithPath:root+"/AppIcon.png"))

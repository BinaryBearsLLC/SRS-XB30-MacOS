import AppKit
import SwiftUI
@main struct NativeReview {
    @MainActor static func main() {
        let app=NSApplication.shared;app.setActivationPolicy(.prohibited)
        let output=URL(fileURLWithPath:CommandLine.arguments[1]);try! FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        func render<V:View>(_ root: V, name:String, size:NSSize) {
            let view=NSHostingView(rootView:root.environment(\.controlActiveState,.active))
            let window=NSWindow(contentRect:NSRect(origin:.zero,size:size),styleMask:[.borderless],backing:.buffered,defer:false)
            window.appearance=app.appearance;window.contentView=view;view.frame=NSRect(origin:.zero,size:size);view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until:Date().addingTimeInterval(0.2))
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
        }
        // The same hosting policy as the menubar popover must follow content growth and shrinkage.
        let sizingController=Controller();sizingController.transport.reviewState(connected:true)
        let sizingHost=NSHostingController(rootView:AnyView(ContentView(controller:sizingController).id("closed")))
        sizingHost.sizingOptions=[.preferredContentSize]
        let sizingWindow=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:443),styleMask:[.borderless],backing:.buffered,defer:false)
        sizingWindow.contentViewController=sizingHost
        sizingHost.view.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        let closedHeight=sizingHost.preferredContentSize.height
        sizingHost.rootView=AnyView(ContentView(controller:sizingController,eqExpanded:true).id("open"))
        sizingHost.view.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        let expandedHeight=sizingHost.preferredContentSize.height
        sizingHost.rootView=AnyView(ContentView(controller:sizingController).id("closed-again"))
        sizingHost.view.layoutSubtreeIfNeeded();RunLoop.main.run(until:Date().addingTimeInterval(0.2))
        precondition(closedHeight > 400 && expandedHeight > closedHeight + 100 && abs(sizingHost.preferredContentSize.height-closedHeight)<1,"Popover must grow and shrink with EQ")
        print("Popover sizing: \(closedHeight) → \(expandedHeight) → \(sizingHost.preferredContentSize.height) PASS")
        for dark in [false,true] {
            app.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
            let c=Controller();c.transport.reviewState(connected:true);c.firmware="1.00";c.battery="About 50%";c.lighting="CALM CYAN"
            render(LightingPalette(controller:c),name:"palette-"+(dark ? "dark":"light"),size:NSSize(width:342,height:450))
            render(AboutView(controller:c),name:"about-"+(dark ? "dark":"light"),size:NSSize(width:412,height:500))
        }
        for (name,connected,expanded,details,dark) in [("disconnected-light",false,false,false,false),("connected-light",true,false,false,false),("eq-light",true,true,false,false),("connected-dark",true,false,false,true),("extra-bass-light",true,false,false,false),("battery-full-light",true,false,false,false),("disconnected-dark",false,false,false,true)] {
            app.appearance=NSAppearance(named:dark ? .darkAqua : .aqua)
            let controller=Controller();controller.transport.reviewState(connected:connected)
            controller.battery=name == "battery-full-light" ? "Fully charged" : "Approx. 70%";controller.volume=35
            if name == "extra-bass-light" {
                controller.preset="EXTRA BASS"
                controller.transport.onFrame?(TandemFrame(dataType:0,sequence:0,payload:Data([0x92,0x11,0xff,0xff,0,0,1,1,1,1])))
                RunLoop.main.run(until:Date().addingTimeInterval(0.02))
            }
            let view=NSHostingView(rootView:ContentView(controller:controller,eqExpanded:expanded,detailsExpanded:details).environment(\.controlActiveState,.active))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:440,height:440),styleMask:[.borderless],backing:.buffered,defer:false)
            window.appearance=app.appearance;window.contentView=view
            view.frame=NSRect(origin:.zero,size:view.fittingSize);window.setContentSize(view.fittingSize);view.layoutSubtreeIfNeeded()
            precondition(view.fittingSize.height > 400 && view.fittingSize.height < 650)
            if expanded { precondition(view.fittingSize.height > 500,"Expanded EQ must grow the panel") }
            RunLoop.main.run(until:Date().addingTimeInterval(0.3))
            let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds)!
            view.cacheDisplay(in:view.bounds,to:bitmap)
            try! bitmap.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent(name+".png"))
            print("RENDER \(name) \(view.bounds)")
        }
    }
}

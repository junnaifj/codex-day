import AppKit

@MainActor final class LauncherDelegate: NSObject, NSApplicationDelegate {
    var timer:Timer?
    var launched=false
    let candidates=["/Applications/ChatGPT.app","/Applications/Codex.app"]
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let path=candidates.first(where:{Bundle(path:$0)?.bundleIdentifier=="com.openai.codex"}) else {alert("Official Codex was not found in Applications.");NSApp.terminate(nil);return}
        let appURL=URL(fileURLWithPath:path)
        let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/codesign");process.arguments=["--verify","--strict","--test-requirement","=anchor apple generic and certificate leaf[subject.OU] = \"2DC432GLL2\"",path]
        do {try process.run();process.waitUntilExit();guard process.terminationStatus==0 else{throw NSError(domain:"Signature",code:1)}} catch {alert("Codex's signing identity could not be verified. No changes were made.");NSApp.terminate(nil);return}
        // A launcher never terminates the host or changes its installed bundle.
        if NSRunningApplication.runningApplications(withBundleIdentifier:"com.openai.codex").isEmpty {launch(appURL);return}
        let url=URL(string:"http://127.0.0.1:9341/json/version")!
        URLSession.shared.dataTask(with:url) { [weak self] data,_,_ in
            Task { @MainActor in
                guard let self else{return}
                if data != nil {
                    NSRunningApplication.runningApplications(withBundleIdentifier:"com.openai.codex").first?.activate(options:[])
                    NSApp.terminate(nil)
                } else {
                    self.alert("Codex is currently open without Day. Quit Codex normally once; this launcher will reopen it automatically with Day enabled. For future launches, use Codex with Day. Your official app and its settings stay unchanged.")
                    self.timer=Timer.scheduledTimer(withTimeInterval:1,repeats:true) { [weak self] _ in Task { @MainActor in
                        if NSRunningApplication.runningApplications(withBundleIdentifier:"com.openai.codex").isEmpty {self?.launch(appURL)}
                    }}
                }
            }
        }.resume()
    }
    func launch(_ url:URL) {
        guard !launched else{return};launched=true;timer?.invalidate()
        let configuration=NSWorkspace.OpenConfiguration();configuration.arguments=["--remote-debugging-address=127.0.0.1","--remote-debugging-port=9341"]
        NSWorkspace.shared.openApplication(at:url,configuration:configuration) { _,error in Task { @MainActor in
            if let error {self.alert(error.localizedDescription)}
            NSApp.terminate(nil)
        }}
    }
    func alert(_ message:String) {let alert=NSAlert();alert.messageText="Codex with Day";alert.informativeText=message;alert.addButton(withTitle:"OK");NSApp.activate(ignoringOtherApps:true);alert.runModal()}
}
@main struct DayLauncher {
    @MainActor static func main(){let app=NSApplication.shared;let delegate=LauncherDelegate();app.delegate=delegate;withExtendedLifetime(delegate){app.run()}}
}

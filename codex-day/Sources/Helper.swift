import AppKit
import SwiftUI
import Darwin

@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var store: DayStore!
    var timer: Timer?
    var lockFD: Int32 = -1
    let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Codex Day")
    func applicationDidFinishLaunching(_ notification:Notification) {
        NSApp.setActivationPolicy(.accessory)
        do {
            try FileManager.default.createDirectory(at:base.appendingPathComponent("requests"),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            try FileManager.default.createDirectory(at:base.appendingPathComponent("responses"),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            lockFD=open(base.appendingPathComponent("helper.lock").path,O_CREAT|O_RDWR,0o600)
            guard lockFD >= 0,flock(lockFD,LOCK_EX|LOCK_NB)==0 else{NSApp.terminate(nil);return}
            store=DayStore()
            timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in Task { @MainActor in self?.processRequests() } }
        } catch {NSApp.terminate(nil)}
    }
    func snapshot()->[String:Any] {
        let encoder=JSONEncoder()
        func objects(_ tasks:[DayTask])->Any { (try? JSONSerialization.jsonObject(with:encoder.encode(tasks))) ?? [] }
        return ["tasks":objects(store.tasks),"suggestions":objects(store.suggestions),"events":store.events.map { e -> [String:Any] in
            ["id":e.eventIdentifier ?? UUID().uuidString,"title":e.title ?? "Untitled","calendar":e.calendar.title,"start":ISO8601DateFormatter().string(from:e.startDate),"end":ISO8601DateFormatter().string(from:e.endDate),"allDay":e.isAllDay]
        },"calendarConnected":store.calendarConnected,"remindersConnected":store.remindersConnected,"busy":store.busy,"status":store.status,"error":store.error ?? "","date":dayKey(store.selected)]
    }
    func processRequests() {
        let files=(try? FileManager.default.contentsOfDirectory(at:base.appendingPathComponent("requests"),includingPropertiesForKeys:nil)) ?? []
        for file in files.prefix(32) where file.pathExtension=="json" && UUID(uuidString:file.deletingPathExtension().lastPathComponent) != nil {
            var response:[String:Any]
            do {
                guard let attributes=try? FileManager.default.attributesOfItem(atPath:file.path),let size=attributes[.size] as? Int,size<131072,attributes[.type] as? FileAttributeType == .typeRegular else{continue}
                let data=try Data(contentsOf:file)
                guard let request=try JSONSerialization.jsonObject(with:data) as? [String:Any],let op=request["op"] as? String else{throw NSError(domain:"Request",code:1)}
                if let date=request["date"] as? String,let parsed=dayFormatter.date(from:date) {store.selected=parsed;store.refreshEvents()}
                switch op {
                case "state":store.loadSuggestions()
                case "calendar.connect":store.connectCalendar()
                case "reminders.connect":store.connectReminders()
                case "daily.check":store.summarize()
                case "task.save":
                    guard let object=request["task"] as? [String:Any] else{throw NSError(domain:"Task",code:1)}
                    var task=try JSONDecoder().decode(DayTask.self,from:JSONSerialization.data(withJSONObject:object))
                    guard !task.title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,task.title.count<=500,task.notes.count<=10000 else{throw NSError(domain:"Task",code:2)}
                    if let original=store.tasks.first(where:{$0.id==task.id}) {task.reminderID=original.reminderID;task.sourceID=original.sourceID;task.sourceTitle=original.sourceTitle;task.evidence=original.evidence}
                    else if let original=store.suggestions.first(where:{$0.id==task.id}) {task.reminderID=nil;task.sourceID=original.sourceID;task.sourceTitle=original.sourceTitle;task.evidence=original.evidence}
                    else {task.reminderID=nil;task.sourceID=nil;task.sourceTitle=nil;task.evidence=nil}
                    store.error=nil
                    if store.suggestions.contains(where:{$0.id==task.id}) {store.accept(task)} else {store.upsert(task)}
                case "task.delete":if let id=request["id"] as? String,let task=store.tasks.first(where:{$0.id==id}){store.error=nil;store.remove(task)}
                case "suggestion.dismiss":if let id=request["id"] as? String,let task=store.suggestions.first(where:{$0.id==id}){store.dismiss(task)}
                case "error.dismiss":store.error=nil
                default:throw NSError(domain:"Request",code:2)
                }
                response=snapshot()
            } catch {response=["error":"The request could not be processed. No unrelated data was changed."]}
            let output=base.appendingPathComponent("responses").appendingPathComponent(file.lastPathComponent)
            if let data=try? JSONSerialization.data(withJSONObject:response) {try? data.write(to:output,options:.atomic)}
            try? FileManager.default.removeItem(at:file)
        }
    }
}
@main struct Helper {
    @MainActor static func main() {
        let app=NSApplication.shared
        let delegate=Delegate();app.delegate=delegate
        withExtendedLifetime(delegate){app.run()}
    }
}

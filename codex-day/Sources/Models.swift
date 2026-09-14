import SwiftUI
import EventKit

struct DayTask: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var title: String
    var notes: String = ""
    var date: String? = nil
    var done = false
    var sourceID: String? = nil
    var sourceTitle: String? = nil
    var evidence: String? = nil
    var reminderID: String? = nil
}
struct SummaryResult: Codable {
    var tasks: [DayTask]
    var conversationCount: Int
    var unreadableCount: Int
    var scope: String
}
// Suggestions begin unchecked; user decisions are stored independently.
extension DayTask {
    enum CodingKeys: String, CodingKey { case id,title,notes,date,done,sourceID,sourceTitle,evidence,reminderID }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        date = try c.decodeIfPresent(String.self, forKey: .date)
        done = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        sourceID = try c.decodeIfPresent(String.self, forKey: .sourceID)
        sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle)
        evidence = try c.decodeIfPresent(String.self, forKey: .evidence)
        reminderID = try c.decodeIfPresent(String.self, forKey: .reminderID)
    }
}
struct SavedState: Codable { var tasks: [DayTask]; var suggestions: [DayTask]; var reviewed: Set<String> }
let dayFormatter: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f }()
func dayKey(_ date: Date) -> String { dayFormatter.string(from: date) }

@MainActor final class DayStore: ObservableObject {
    @Published var tasks: [DayTask] = []
    @Published var suggestions: [DayTask] = []
    @Published var selected = Date()
    @Published var month = Date()
    @Published var events: [EKEvent] = []
    @Published var calendarConnected = false
    @Published var remindersConnected = false
    @Published var busy = false
    @Published var status = "Your day, thoughtfully arranged."
    @Published var error: String?
    var reviewed: Set<String> = []
    let eventStore = EKEventStore()
    let storage: URL
    let suggestionFile: URL
    var observer: NSObjectProtocol?
    var wakeObserver: NSObjectProtocol?
    var timer: Timer?
    var lastSuggestionData: Data?
    var writable = true
    var syncing = false
    var revision = 0
    var lastAttemptDay = ""
    init() {
        let base=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Codex Day")
        storage=base.appendingPathComponent("tasks.json")
        suggestionFile=base.appendingPathComponent("suggestions.json")
        do {
            if FileManager.default.fileExists(atPath:storage.path) {
                let state=try JSONDecoder().decode(SavedState.self,from:Data(contentsOf:storage))
                tasks=state.tasks;reviewed=state.reviewed
            }
        } catch { writable=false;self.error="Saved tasks could not be read. They have been preserved; resolve this before editing." }
        observer=NotificationCenter.default.addObserver(forName:.EKEventStoreChanged,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.refreshEvents();self?.syncReminders() } }
        wakeObserver=NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didWakeNotification,object:nil,queue:.main) { [weak self] _ in Task { @MainActor in self?.tick() } }
        timer=Timer.scheduledTimer(withTimeInterval:30,repeats:true) { [weak self] _ in Task { @MainActor in self?.tick() } }
        refreshEvents();loadSuggestions();syncReminders();tick()
    }
    func tick() {
        refreshEvents();loadSuggestions()
        if lastAttemptDay != dayKey(Date()) { summarize() }
    }
    func loadSuggestions() {
        guard let data=try? Data(contentsOf:suggestionFile),data != lastSuggestionData else { return }
        do {
            let result=try JSONDecoder().decode(SummaryResult.self,from:data)
            lastSuggestionData=data
            let excluded=Set(tasks.map(\.id)).union(reviewed)
            suggestions=result.tasks.filter{!excluded.contains($0.id)}
            status="Daily local scan · \(result.conversationCount) conversations · \(suggestions.count) suggestions" + (result.unreadableCount > 0 ? " · \(result.unreadableCount) unreadable":"")
        } catch { self.error="The daily suggestion file could not be read; existing to-dos are unchanged." }
    }
    func save() {
        guard writable else { return }
        revision += 1
        do {
            try FileManager.default.createDirectory(at:storage.deletingLastPathComponent(),withIntermediateDirectories:true)
            try JSONEncoder().encode(SavedState(tasks:tasks,suggestions:[],reviewed:reviewed)).write(to:storage,options:.atomic)
        } catch { self.error="Could not save changes: \(error.localizedDescription)" }
    }
    func upsert(_ value: DayTask) {
        guard writable else { return }
        var task=value
        do {
            if remindersConnected { try writeReminder(&task) }
            if let i=tasks.firstIndex(where:{$0.id==task.id}) { tasks[i]=task } else { tasks.append(task) }
            save()
        } catch { self.error="Reminders could not save this change: \(error.localizedDescription)" }
    }
    func accept(_ task: DayTask) {
        guard writable else{return};upsert(task)
        guard tasks.contains(where:{$0.id==task.id}) else{return}
        reviewed.insert(task.id);suggestions.removeAll{$0.id==task.id};save()
    }
    func dismiss(_ task: DayTask) { guard writable else{return};reviewed.insert(task.id);suggestions.removeAll{$0.id==task.id};save() }
    func remove(_ task: DayTask) {
        guard writable else{return}
        do {
            if let id=task.reminderID {
                guard remindersConnected else { throw NSError(domain:"Reminders",code:1,userInfo:[NSLocalizedDescriptionKey:"Reconnect Reminders before deleting a synced task."]) }
                if let reminder=eventStore.calendarItem(withIdentifier:id) as? EKReminder, reminder.calendar.calendarIdentifier == UserDefaults.standard.string(forKey:"reminderCalendar") { try eventStore.remove(reminder,commit:true) }
            }
            reviewed.insert(task.id);tasks.removeAll{$0.id==task.id};save()
        } catch { self.error=error.localizedDescription }
    }
    func connectCalendar() {
        Task { do {
            calendarConnected=try await eventStore.requestFullAccessToEvents()
            if calendarConnected {refreshEvents()} else {error="Allow Codex Day in System Settings → Privacy & Security → Calendars."}
        } catch {self.error=error.localizedDescription} }
    }
    func refreshEvents() {
        calendarConnected=EKEventStore.authorizationStatus(for:.event) == .fullAccess
        guard calendarConnected else{events=[];return}
        let start=Calendar.current.startOfDay(for:selected), end=Calendar.current.date(byAdding:.day,value:1,to:start)!
        events=eventStore.events(matching:eventStore.predicateForEvents(withStart:start,end:end,calendars:nil)).sorted{$0.startDate < $1.startDate}
    }
    func connectReminders() {
        Task { do {
            if try await eventStore.requestFullAccessToReminders() {
                _ = try reminderCalendar(create:true)
                remindersConnected=true;syncReminders()
            } else { error="Allow Codex Day in System Settings → Privacy & Security → Reminders." }
        } catch {self.error=error.localizedDescription} }
    }
    func reminderCalendar(create:Bool) throws -> EKCalendar? {
        if let id=UserDefaults.standard.string(forKey:"reminderCalendar"),let cal=eventStore.calendar(withIdentifier:id) {return cal}
        guard create else{return nil}
        guard let source=eventStore.defaultCalendarForNewReminders()?.source ?? eventStore.sources.first(where:{$0.sourceType == .local}) else {
            throw NSError(domain:"Reminders",code:1,userInfo:[NSLocalizedDescriptionKey:"Open Apple Reminders and set up an account first."])
        }
        let cal=EKCalendar(for:.reminder,eventStore:eventStore);cal.title="Codex Day";cal.source=source
        try eventStore.saveCalendar(cal,commit:true)
        UserDefaults.standard.set(cal.calendarIdentifier,forKey:"reminderCalendar");return cal
    }
    func writeReminder(_ task:inout DayTask) throws {
        guard let cal=try reminderCalendar(create:false) else {throw NSError(domain:"Reminders",code:2,userInfo:[NSLocalizedDescriptionKey:"The Codex Day list is unavailable. Reconnect Reminders."])}
        let existing=task.reminderID.flatMap{eventStore.calendarItem(withIdentifier:$0) as? EKReminder}
        if let existing,existing.calendar.calendarIdentifier != cal.calendarIdentifier {throw NSError(domain:"Reminders",code:3,userInfo:[NSLocalizedDescriptionKey:"This reminder was moved to another list. Refresh first."])}
        let reminder=existing ?? EKReminder(eventStore:eventStore)
        reminder.calendar=cal;reminder.title=task.title;reminder.notes=task.notes;reminder.isCompleted=task.done
        if let date=task.date.flatMap({dayFormatter.date(from:$0)}) {
            reminder.dueDateComponents=Calendar.current.dateComponents([.year,.month,.day],from:date)
        } else {reminder.dueDateComponents=nil}
        try eventStore.save(reminder,commit:true);task.reminderID=reminder.calendarItemIdentifier
    }
    func syncReminders() {
        remindersConnected=EKEventStore.authorizationStatus(for:.reminder) == .fullAccess && UserDefaults.standard.string(forKey:"reminderCalendar") != nil
        guard remindersConnected,writable,!syncing else{return}
        guard let cal=try? reminderCalendar(create:false) else {remindersConnected=false;return}
        syncing=true
        let snapshotRevision=revision
        eventStore.fetchReminders(matching:eventStore.predicateForReminders(in:[cal])) { [weak self] reminders in
            Task { @MainActor in
                guard let self else{return};self.syncing=false
                guard let reminders else {return}
                if self.revision != snapshotRevision {self.syncReminders();return}
                let ids=Set(reminders.map(\.calendarItemIdentifier))
                self.tasks.removeAll{task in
                    if let id=task.reminderID,!ids.contains(id) {self.reviewed.insert(task.id);return true};return false
                }
                for reminder in reminders {
                    let index=self.tasks.firstIndex{$0.reminderID==reminder.calendarItemIdentifier}
                    var task=index.map{self.tasks[$0]} ?? DayTask(title:reminder.title ?? "Untitled")
                    task.reminderID=reminder.calendarItemIdentifier;task.title=reminder.title ?? "Untitled";task.notes=reminder.notes ?? "";task.done=reminder.isCompleted
                    task.date=reminder.dueDateComponents.flatMap{Calendar.current.date(from:$0)}.map(dayKey)
                    if let index {self.tasks[index]=task} else {self.tasks.append(task)}
                }
                for i in self.tasks.indices where self.tasks[i].reminderID == nil {
                    do { try self.writeReminder(&self.tasks[i]) } catch {self.error=error.localizedDescription}
                }
                self.save()
            }
        }
    }
    func summarize() {
        guard !busy else{return};busy=true;lastAttemptDay=dayKey(Date());status="Checking daily local suggestions…"
        guard let script=Bundle.main.url(forResource:"summarize",withExtension:"py") else{busy=false;return}
        let outputPath=suggestionFile.path
        Task {
            let result=await Task.detached { () -> Result<Void,Error> in
                do {
                    let process=Process();process.executableURL=URL(fileURLWithPath:"/usr/bin/python3");process.arguments=[script.path,"--daily","--output",outputPath]
                    let output=Pipe();process.standardOutput=output;process.standardError=FileHandle.nullDevice
                    try process.run();let data=output.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
                    if process.terminationStatus != 0 {
                        let payload=(try? JSONSerialization.jsonObject(with:data)) as? [String:String]
                        throw NSError(domain:"Summary",code:1,userInfo:[NSLocalizedDescriptionKey:payload?["error"] ?? "Local scan could not finish."])
                    }
                    return .success(())
                } catch{return .failure(error)}
            }.value
            busy=false
            do {try result.get();lastSuggestionData=nil;loadSuggestions()} catch {self.error=error.localizedDescription;status="Daily scan unavailable. Your to-dos are unchanged."}
        }
    }
}

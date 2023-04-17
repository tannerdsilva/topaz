import QuickLMDB
import Logging
import Foundation

/// A Task scheduler that uses LMDB to store and time scheduled tasks.
/// - Ideally used with a ``QuickLMDB/Environment`` that has a ``QuickLMDB/Environment/Flags/noSync`` flag set, since Scheduler does not need sync to disk every time it writes to the database
public class Scheduler {
	/// Defines the exclusivity level a scheduler may have
	public enum ExclusivityLevel:UInt8, MDB_convertible {
		/// Do not check the scheduler for exclusivity and blindly assume that the scheduler is the only one running
		case noCheck = 0
		/// The scheduler will only check for stale PID's that match the currently running PID
		case pidExclusive = 1
		/// The scheduler will ensure it is the only instance running for the current user
		case userExclusive = 2
		/// The scheduler will ensure it is the only instance running on the current machine
		/// - NOTE: your process MUST have the ability to signal any process on the machine to ensure this exclusivity level is met
		case systemExclusive = 3
	}

	/// Defines the unique errors that can be thrown by the scheduler
	public enum Error:Swift.Error {
		/// The specified exclusivity level could not be met
		case exclusivityRequirementsNotMet

		/// The given PID is already running the scpecified schedule
		case scheduleAlreadyRunning(pid_t)
	}

	/// The logger used for this scheduler
	public static var logger = Topaz.makeDefaultLogger(label:"lmdb-scheduler")
	
	/// The named databases that the Task scheduler uses
	internal enum Databases:String {
		// registration related databases
		case pid_exclusivity_db = "#sched#pid_exclusivity_db"		// [pid_t:ExclusivityLevel]	(no overwrite)
		case user_pid = "#sched#user_pid_db"						// [String:pid_t]			* DUP *	(no dup data)
		case pid_user = "#sched#pid_user_db"						// [pid_t:String]			(no overwrite)
		
		// task related databases
		case schedule_pid = "#sched#schedule_pid_db"				// [String:pid_t]			(no overwrite)
		case pid_schedule = "#sched#pid_schedule-name_db"			// [String:String]			* DUP * (no dup data)
		case schedule_tasks = "#sched#schedule_task_db"				// [String:Task]			(no overwrite)
		case schedule_lastFire = "#sched#schedule_lastfire_db"		// [String:Date]			[NEVER DELETE]
	}
	
	internal let env:Environment
	
	// registration related databases (involving a given process verifying its exclusivity and registering itself with the scheduler)
	/// the databsae that stores the exclusivity level for a given process
	internal let pid_exclusivity:Database
	/// stores the username and pid the running processes with any scheduled tasks
	internal let user_pid:Database
	/// stores the username for each pid
	internal let pid_user:Database
	
	// task related databases (involving a given task and its scheduling for a process that has already been registered)
	// stores the pid for each task
	internal let schedule_pid:Database
	/// stores the task name for each pid
	internal let pid_schedule:Database
	/// stores the actual Task struct for a given task
	internal let schedule_task:Database
	/// stores the last fire date for a given task
	internal let schedule_lastFire:Database

	/// initialize a Task scheduler with an ``QuickLMDB/Environment`` and write-enabled Transaction
	/// - if this is being initialized, the scheduler will assume that it has exclusive rights to manage (add, delete, modify, reschedule) tasks for the currently running user
	/// - other users with scheduled content in the database will not be affected
	public init(env:Environment, exclusivity:ExclusivityLevel = .userExclusive, tx someTrans:Transaction) throws {

#if DEBUG
		// notify the developer that their process must meet the signal requirements to use the systemExclusive exclusivity level
		if (exclusivity == .systemExclusive) {
			Self.logger.notice("The systemExclusive exclusivity level requires that your process be able to signal ANY PROCESS on the machine. If this is not the case, you should use a lower exclusivity level or elevate your process's capabilities.")
		}
#endif

		// capture the current user before opening a transaction
		let curUser = getCurrentUser()
		let myPID = getpid()

		// open a subtransaction
		let subTrans = try Transaction(env, readOnly:false, parent:someTrans)
		self.env = env

		// open the databases related to registration
		self.pid_exclusivity = try env.openDatabase(named:Databases.user_pid.rawValue, flags:[.create], tx:subTrans)
		self.user_pid = try env.openDatabase(named:Databases.user_pid.rawValue, flags:[.create, .dupSort], tx:subTrans)
		self.pid_user = try env.openDatabase(named:Databases.pid_user.rawValue, flags:[.create], tx:subTrans)
		
		// open the databases related to active tasks
		self.schedule_pid = try env.openDatabase(named:Databases.schedule_pid.rawValue, flags:[.create], tx:subTrans)
		self.pid_schedule = try env.openDatabase(named:Databases.pid_schedule.rawValue, flags:[.create, .dupSort], tx:subTrans)
		self.schedule_task = try env.openDatabase(named:Databases.schedule_tasks.rawValue, flags:[.create], tx:subTrans)
		self.schedule_lastFire = try env.openDatabase(named:Databases.schedule_lastFire.rawValue, flags:[.create], tx:subTrans)
		
		switch exclusivity {
			case .pidExclusive:
				// verify that the exact PID does not have any existing entries in the database
				let pid_cursor = try pid_exclusivity.cursor(tx:subTrans)
				let pidu_cursor = try pid_user.cursor(tx:subTrans)

				// scan all the pid entries in the database
				for (curPIDVal, curExcVal) in pid_cursor {
					let curPID = pid_t(curPIDVal)!
					let curExclusivity = ExclusivityLevel(curExcVal)!

					if (curExclusivity.rawValue > exclusivity.rawValue) {
						// the current PID has a higher exclusivity level than the one we're trying to register
						// we need to check if the PID is running
						let checkPID = kill(curPID, 0)
						if (checkPID == 0) {
							// the PID is running, so we can't register our process
							Self.logger.error("unable to initialize new instance. exclusivity requirements could not be met.", metadata: [
								"exclusivity": "\(exclusivity)",
								"currentPID": "\(myPID)",
								"currentUserID": "\(curUser)",
								"conflictingPID": "\(curPID)",
								"killResult": "\(checkPID)"
							])
							throw Error.exclusivityRequirementsNotMet
						} else {
							// the PID is not running, so we can remove it from the database
							let curUser = try pidu_cursor.getEntry(.set, key:curPIDVal).value
							try self.user_pid.deleteEntry(key:curUser, tx:subTrans)
							try pidu_cursor.deleteEntry()
							try pid_cursor.deleteEntry()

							// we must also remove any scheduled tasks for this PID
							do {
								let sched_cursor = try pid_schedule.cursor(tx:subTrans)
								for (_, curSchedVal) in try sched_cursor.makeDupIterator(key: curPID) {
									try schedule_task.deleteEntry(key:curSchedVal, tx:subTrans)
									try schedule_pid.deleteEntry(key:curSchedVal, tx:subTrans)
									try sched_cursor.deleteEntry()
								}
							} catch LMDBError.notFound {}
						}
					}
				}
				// validation passed. document this process in the database
				try pid_exclusivity.setEntry(value:exclusivity, forKey:myPID, flags:[.noOverwrite], tx:subTrans)
				try user_pid.setEntry(value:myPID, forKey:curUser, flags:[.noDupData], tx:subTrans)
				try pid_user.setEntry(value:curUser, forKey:myPID, flags:[.noOverwrite], tx:subTrans)

			case .userExclusive:
				// verify that the current user does not have any running processes
				let userPIDCursor = try user_pid.cursor(tx:subTrans)
				let makeDupIterator:Cursor.CursorDupIterator
				do {
					makeDupIterator = try userPIDCursor.makeDupIterator(key: curUser)
				} catch LMDBError.notFound {
					// no entries for this user. we can proceed
					return
				}
				for (curUser, curPIDVal) in makeDupIterator {
					let curPID = pid_t(curPIDVal)!
					// validate that the PID is not running
					let checkPID = kill(curPID, 0)
					guard checkPID != 0 else {
						Self.logger.error("unable to initialize new instance. exclusivity requirements could not be met.", metadata: [
							"exclusivity": "\(exclusivity)",
							"currentPID": "\(myPID)",
							"currentUserID": "\(curUser)",
							"conflictingPID": "\(curPID)",
							"killResult": "\(checkPID)"
						])
						throw Error.exclusivityRequirementsNotMet
					}

					// the PID is not running, so we can remove it from the database
					try pid_exclusivity.deleteEntry(key:curPIDVal, tx:subTrans)
					try pid_user.deleteEntry(key:curPIDVal, tx:subTrans)
					let pid_scheduleCursor = try pid_schedule.cursor(tx:subTrans)
					do {
						// remove any scheduled tasks for this PID
						for (_, curScheduleName) in try pid_scheduleCursor.makeDupIterator(key: curPID) {
							try schedule_task.deleteEntry(key:curScheduleName, tx:subTrans)
							try schedule_pid.deleteEntry(key:curScheduleName, tx:subTrans)
							try pid_scheduleCursor.deleteEntry()
						}
					} catch LMDBError.notFound {}
					try userPIDCursor.deleteEntry()
				}
				// validation passed. document this process in the database
				try pid_exclusivity.setEntry(value:exclusivity, forKey:myPID, tx:subTrans)
				try user_pid.setEntry(value:myPID, forKey:curUser, flags:[.noDupData], tx:subTrans)
				try pid_user.setEntry(value:curUser, forKey:myPID, flags:[.noOverwrite], tx:subTrans)
			case .systemExclusive:
				let pidEx_cursor = try self.pid_exclusivity.cursor(tx:subTrans)
				// scan all the pid entries in the database
				for (curPIDVal, _) in pidEx_cursor {
					let asPID = pid_t(curPIDVal)!

					// verify that the process is not running
					let checkPID = kill(asPID, 0)
					guard checkPID != 0 else {
						Self.logger.error("unable to initialize new instance. exclusivity requirements could not be met.", metadata: [
							"exclusivity": "\(exclusivity)",
							"currentPID": "\(myPID)",
							"conflictingPID": "\(asPID)",
							"killResult": "\(checkPID)"
						])
						throw Error.exclusivityRequirementsNotMet
					}
				}
				// validation passed.
				fallthrough
			case .noCheck:
				// delete all the entries in the database
				try self.pid_exclusivity.deleteAllEntries(tx:subTrans)
				try self.pid_user.deleteAllEntries(tx:subTrans)
				try self.user_pid.deleteAllEntries(tx:subTrans)
				try self.schedule_pid.deleteAllEntries(tx:subTrans)
				try self.pid_schedule.deleteAllEntries(tx:subTrans)
				try self.schedule_task.deleteAllEntries(tx:subTrans)

				// document this exclusive process in the database
				try pid_exclusivity.setEntry(value:exclusivity, forKey:myPID, tx:subTrans)
				try user_pid.setEntry(value:myPID, forKey:curUser, flags:[.noDupData], tx:subTrans)
				try pid_user.setEntry(value:curUser, forKey:myPID, flags:[.noOverwrite], tx:subTrans)
		}

		// commit the transaction
		try subTrans.commit()
	}
	
	// MARK: Scheduling
	// launching scheduled tasks
	public func launchScheduledTask<T>(_ task:T) throws where T:TaskProtocol {
		let curPID = getpid()
		try env.transact(readOnly:false) { installTaskTrans in
			// ensure that the schedule does not already exist in the database.
			do {
				// ensure that we can assign our PID to the specified schedule name
				try self.schedule_pid.setEntry(value:curPID, forKey:task.configuration.name, flags:[.noOverwrite], tx:installTaskTrans)
				try self.pid_schedule.setEntry(value:task.configuration.name, forKey:curPID, flags:[.noDupData], tx:installTaskTrans)

				// determine the next fire date for the schedule
				let nextFire:Date
				do {
					let lastDate = try self.schedule_lastFire.getEntry(type:Date.self, forKey:task.configuration.name, tx:installTaskTrans)!
					nextFire = lastDate.addingTimeInterval(task.configuration.timeInterval)
				} catch LMDBError.notFound {
					nextFire = Date()
				}
				
				// launch the task and save it in the database
				let newTask = Task<(), Swift.Error>.detached { [mdbEnv = env, lastFire = self.schedule_lastFire, referenceDate = nextFire, taskIn = task] in
					// setup the async task
					var mutableTask = taskIn
					var nextTarget = referenceDate
					while Task.isCancelled == false {
						// calculate how much time needs to pass before the next run. wait that long.
						let delayTime = nextTarget.timeIntervalSinceNow
						if delayTime > 0 {
							try await Task.sleep(nanoseconds: UInt64(delayTime * 1_000_000_000))
						} else if (abs(delayTime) > mutableTask.configuration.timeInterval) {
							nextTarget = Date()
						}
#if DEBUG
						Self.logger.info("running task.", metadata: [
							"task": "\(mutableTask.configuration.name)",
							"nextTarget": "\(nextTarget)",
							"delayTime": "\(delayTime)"
						])
#endif
						// run the task and document the next fire date once it is complete
						try await mutableTask.work()
						let futureTask = nextTarget.addingTimeInterval(mutableTask.configuration.timeInterval)
#if DEBUG
						Self.logger.info("task done running.", metadata: [
							"task": "\(mutableTask.configuration.name)",
							"nextTarget": "\(nextTarget)",
							"futureTask": "\(futureTask)",
							"delayTime": "\(delayTime)"
						])
#endif
						// update the database with the latest fire date
						try mdbEnv.transact(readOnly:false) { someTrans in
							try lastFire.setEntry(value:nextTarget, forKey:mutableTask.configuration.name, tx:someTrans)
						}
						nextTarget = futureTask
					}
				}

				// write the task to the database
				try self.schedule_task.setEntry(value:newTask, forKey:task.configuration.name, tx:installTaskTrans)
			} catch LMDBError.keyExists {
				let getPID = try schedule_pid.getEntry(type:pid_t.self, forKey:task.configuration.name, tx:installTaskTrans)!
				throw Error.scheduleAlreadyRunning(getPID)
			}
		}
		// sync the database if noSync is enabled
		if env.flags.contains(.noSync) == true {
			try env.sync()
		}
	}
	
	// canceling scheduled task
	public func cancelSchedule(_ name:String) throws {
		// open a write transaction
		try env.transact(readOnly:false) { someTrans in
			let loadTask = try self.schedule_task.getEntry(type:Task<(), Swift.Error>.self, forKey:name, tx:someTrans)!
			loadTask.cancel()
			try self.schedule_task.deleteEntry(key:name, tx:someTrans)
		}

		// sync the database if noSync is enabled
		if env.flags.contains(.noSync) == true {
			try env.sync()
		}
	}
	
	deinit {
		try! self.env.transact(readOnly:false) { someTrans in
			try self.schedule_task.deleteAllEntries(tx:someTrans)
		}
		Self.logger.trace("instance deinitialized")
	}
}



//// MARK: - ExclusivityLevel & MDB_convertible
//extension Scheduler.ExclusivityLevel:LosslessStringConvertible, MDB_convertible {
//	public init?(_ description: String) {
//		guard let asRawVal = UInt8(description) else {
//			return nil
//		}
//		self.init(rawValue:asRawVal)
//	}
//
//	public var description: String {
//		return String(self.rawValue)
//	}
//}

// MARK: - Swift.Task & MDB_convertible
extension Task:MDB_convertible {
	public init?(_ value: MDB_val) {
		guard MemoryLayout<Self>.stride == value.mv_size else {
			return nil
		}
		self = value.mv_data.bindMemory(to:Self.self, capacity:1).pointee
	}
	
	public func asMDB_val<R>(_ valFunc: (inout MDB_val) throws -> R) rethrows -> R {
		return try withUnsafePointer(to:self, { unsafePointer in
			var newVal = MDB_val(mv_size:MemoryLayout<Self>.stride, mv_data:UnsafeMutableRawPointer(mutating:unsafePointer))
			return try valFunc(&newVal)
		})
	}
}


/// returns the username that the calling process is running as
fileprivate func getCurrentUser() -> String {
	return String(validatingUTF8:getpwuid(geteuid()).pointee.pw_name)!
}

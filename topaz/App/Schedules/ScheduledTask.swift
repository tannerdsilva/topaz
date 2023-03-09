import Logging
import Foundation

/// A ScheduledTask is a type that can be scheduled to run at a given time interval.
public protocol TaskProtocol {
	/// Relevant logger for a given ScheduledTask
	static var logger:Logger { get }
	
	/// Defines the configuration parameters for a task type
	var configuration:ScheduledTask.Configuration { get }
	
	/// The function that actually executes the work.
	mutating func work() async throws
}

public struct ScheduledTask {
	public struct Configuration {
		/// the name of the task
		let name:String

		/// the time interval (represented as time)
		/// - Note: TaskProtocol clients may not modify this value if they are not `work()`ing 
		let timeInterval:TimeInterval
	}
}

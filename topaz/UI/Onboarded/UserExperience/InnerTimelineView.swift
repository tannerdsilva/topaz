
import SwiftUI

struct InnerTimelineView: View {
	@ObservedObject var ue:UE
	@State var nav_target:nostr.Event? = nil
	@State var navigating:Bool = false
	
	var MaybeBuildThreadView: some View {
		Group {
			if let ev = nav_target {
//				BuildThreadV2View(ue:ue, event_id: (ev.inner_event ?? ev).id)
			} else {
				EmptyView()
			}
		}
	}
	
	var body: some View {
		NavigationLink(destination: MaybeBuildThreadView, isActive: $navigating) {
			EmptyView()
		}
		let getEvents = ue.eventsDB.getEvents()
		switch getEvents {
		case let .success(result):
			ForEach(result) { curEv in
				EventView(ue:ue, event:curEv)
			}
		case let .failure(error):
			Text("NO")
		}
		
		
	}
}


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
//
//
//struct InnerTimelineView_Previews: PreviewProvider {
//	static var previews: some View {
//		InnerTimelineView(events: test_event_holder, damus: test_damus_state(), show_friend_icon: true, filter: { _ in true }, nav_target: nil, navigating: false)
//			.frame(width: 300, height: 500)
//			.border(Color.red)
//	}
//}

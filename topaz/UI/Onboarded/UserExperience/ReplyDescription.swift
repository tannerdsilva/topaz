//
//  ReplyDescription.swift
//  topaz
//
//  Created by Tanner Silva on 3/11/23.
//

import Foundation
import SwiftUI

struct ReplyDescription: View {
	let ue:UE
	let event:nostr.Event
	
	var body: some View {
		Text(verbatim: "\(reply_desc(ue:ue, event: event))")
			.font(.footnote)
			.foregroundColor(.gray)
			.frame(maxWidth: .infinity, alignment: .leading)
	}
}

struct ReplyDescription_Previews: PreviewProvider {
	static var previews: some View {
		ReplyDescription(ue:try! UE(keypair:Topaz.tester_account), event: test_event)
	}
}

func reply_desc(ue:UE, event:nostr.Event, locale: Locale = Locale.current) -> String {
	let desc = make_reply_description(event.tags.compactMap({ $0.toArray() }))
	let pubkeys = desc.pubkeys
	let n = desc.others

	let bundle = bundleForLocale(locale: locale)

	if desc.pubkeys.count == 0 {
		return NSLocalizedString("Replying to self", bundle: bundle, comment: "Label to indicate that the user is replying to themself.")
	}

	let names: [String] = pubkeys.map {
		let prof = try? ue.profilesDB.getPublicKeys(publicKeys: Set([$0])).first!.value
		return nostr.Profile.displayName(profile: prof, pubkey: $0)
	}

	if names.count > 1 {
		let othersCount = n - pubkeys.count
		if othersCount == 0 {
			return String(format: NSLocalizedString("Replying to %@ & %@", bundle: bundle, comment: "Label to indicate that the user is replying to 2 users."), locale: locale, names[0], names[1])
		} else {
			return String(format: bundle.localizedString(forKey: "replying_to_two_and_others", value: nil, table: nil), locale: locale, othersCount, names[0], names[1])
		}
	}

	return String(format: NSLocalizedString("Replying to %@", bundle: bundle, comment: "Label to indicate that the user is replying to 1 user."), locale: locale, names[0])
}



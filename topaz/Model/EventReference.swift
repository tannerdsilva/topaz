//
//  EventReference.swift
//  topaz
//
//  Created by Tanner Silva on 3/11/23.
//

import Foundation

enum EventReference {
	case mention(nostr.Mention)
	case thread_id(nostr.ReferenceID)
	case reply(nostr.ReferenceID)
	case reply_to_root(nostr.ReferenceID)
	
	var is_mention:nostr.Mention? {
		if case .mention(let m) = self {
			return m
		}
		return nil
	}
	
	var is_direct_reply: nostr.ReferenceID? {
		switch self {
		case .mention:
			return nil
		case .thread_id:
			return nil
		case .reply(let refid):
			return refid
		case .reply_to_root(let refid):
			return refid
		}
	}
	
	var is_thread_id: nostr.ReferenceID? {
		switch self {
		case .mention:
			return nil
		case .thread_id(let referencedId):
			return referencedId
		case .reply:
			return nil
		case .reply_to_root(let referencedId):
			return referencedId
		}
	}
	
	var is_reply: nostr.ReferenceID? {
		switch self {
		case .mention:
			return nil
		case .thread_id:
			return nil
		case .reply(let refid):
			return refid
		case .reply_to_root(let refid):
			return refid
		}
	}
}

func has_any_e_refs(_ tags: [[String]]) -> Bool {
	for tag in tags {
		if tag.count >= 2 && tag[0] == "e" {
			return true
		}
	}
	return false
}

func build_mention_indices(_ blocks: [nostr.Event.Block], type:nostr.Mention.Kind) -> Set<Int> {
	return blocks.reduce(into: []) { acc, block in
		switch block {
		case .mention(let m):
			if m.type == type {
				acc.insert(m.index)
			}
		case .text:
			return
		case .hashtag:
			return
		case .url:
			return
		case .invoice:
			return
		}
	}
}

func interp_event_refs_without_mentions(_ refs: [nostr.ReferenceID]) -> [EventReference] {
	if refs.count == 0 {
		return []
	}

	if refs.count == 1 {
		return [.reply_to_root(refs[0])]
	}
	
	var evrefs: [EventReference] = []
	var first: Bool = true
	for ref in refs {
		if first {
			evrefs.append(.thread_id(ref))
			first = false
		} else {
			evrefs.append(.reply(ref))
		}
	}
	return evrefs
}

func get_referenced_ids(tags: [[String]], key: String) -> [nostr.ReferenceID] {
	return tags.reduce(into: []) { (acc, tag) in
		if tag.count >= 2 && tag[0] == key {
			var relay_id: String? = nil
			if tag.count >= 3 {
				relay_id = tag[2]
			}
			acc.append(nostr.ReferenceID(ref_id: tag[1], relay_id: relay_id, key: key))
		}
	}
}
func interp_event_refs_with_mentions(tags: [[String]], mention_indices: Set<Int>) -> [EventReference] {
	var mentions: [EventReference] = []
	var ev_refs: [nostr.ReferenceID] = []
	var i: Int = 0
	
	for tag in tags {
		if tag.count >= 2 && tag[0] == "e" {
			if let ref = try? nostr.Event.Tag(tag).toReference() {
				if mention_indices.contains(i) {
					let mention = nostr.Mention(index: i, type: nostr.Mention.Kind.event, ref: ref)
					mentions.append(.mention(mention))
				} else {
					ev_refs.append(ref)
				}
			}
		}
		i += 1
	}
	
	var replies = interp_event_refs_without_mentions(ev_refs)
	replies.append(contentsOf: mentions)
	return replies
}

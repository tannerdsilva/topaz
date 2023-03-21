//
//  Zap.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import Foundation
import Ctopaz

struct NoteZapTarget:Equatable, Codable, Hashable {
	let note_id: String
	let author: String
}

struct Zap:Codable {
	enum Kind {
		case pub
		case anon
		case priv
		case non_zap
	}

	struct Request:Equatable, Codable, Hashable {
		let ev:nostr.Event
	}
	
	public let event:nostr.Event
	public let invoice:LightningInvoice<Int64>
	public let zapper:String /// zap authorizer
	public let target:Target
	public let request:Request
	public let is_anon:Bool
	public let private_request:nostr.Event?
	
	public static func from_zap_event(zap_ev:nostr.Event, zapper:String, our_privkey:String?) -> Zap? {
		/// Make sure that we only create a zap event if it is authorized by the profile or event
		guard zapper == zap_ev.pubkey else {
			return nil
		}
		guard let bolt11_str = event_tag(zap_ev, name: "bolt11") else {
			return nil
		}
		guard let bolt11 = decode_bolt11(bolt11_str) else {
			return nil
		}
		/// Any amount invoices are not allowed
		guard let zap_invoice = invoice_to_zap_invoice(bolt11) else {
			return nil
		}
		// Some endpoints don't have this, let's skip the check for now. We're mostly trusting the zapper anyways
		/*
		guard let preimage = event_tag(zap_ev, name: "preimage") else {
			return nil
		}
		guard preimage_matches_invoice(preimage, inv: zap_invoice) else {
			return nil
		}
		 */
		guard let desc = get_zap_description(zap_ev, inv_desc: zap_invoice.description) else {
			return nil
		}
		
		guard let zap_req = decode_nostr_event_json(desc) else {
			return nil
		}
		
		do {
			guard try zap_req.validate() == .ok else {
				return nil
			}
		} catch {
			return nil
		}
		
		guard let target = determine_zap_target(zap_req) else {
			return nil
		}
		
		let private_request = our_privkey.flatMap {
			decrypt_private_zap(our_privkey: $0, zapreq: zap_req, target: target)
		}
		
		let is_anon = private_request == nil && event_is_anonymous(ev: zap_req)
		
		return Zap(event: zap_ev, invoice: zap_invoice, zapper: zapper, target: target, request: Zap.Request(ev:zap_req), is_anon: is_anon, private_request: private_request)
	}
}

extension Zap {
	public enum Target:Equatable, Codable, Hashable {
		enum Error:Swift.Error {
			case unknownTargetType(Int)
		}
		case profile(String)
		case note(NoteZapTarget)
		
		public static func note(id: String, author: String) -> Target {
			return .note(NoteZapTarget(note_id: id, author: author))
		}
		
		var pubkey: String {
			switch self {
			case .profile(let pk):
				return pk
			case .note(let note_target):
				return note_target.author
			}
		}
		
		var id: String {
			switch self {
			case .note(let note_target):
				return note_target.note_id
			case .profile(let pk):
				return pk
			}
		}

		init(from decoder:Decoder) throws {
			var container = try decoder.unkeyedContainer()
			let type = try container.decode(Int.self)
			switch type {
				case 0: // profile
					let profile_target = try container.decode(String.self)
					self = .profile(profile_target)
				case 1: // note
					let note_target = try container.decode(NoteZapTarget.self)
					self = .note(note_target)
			default:
				throw Error.unknownTargetType(type)
			}
		}

		func encode(to encoder:Encoder) throws {
			var container = encoder.unkeyedContainer()
			switch self {
				case .profile(let profile_target):
					try container.encode(0)
					try container.encode(profile_target)
				case .note(let note_target):
					try container.encode(1)
					try container.encode(note_target)
			}
		}
		
		public func hash(into hasher: inout Hasher) {
			switch self {
			case .note(let noteInfo):
				hasher.combine(1)
				hasher.combine(noteInfo)
			case .profile(let profInfo):
				hasher.combine(0)
				hasher.combine(profInfo)
			}
		}
	}
}

/// Fetches the description from either the invoice, or tags, depending on the type of invoice
func get_zap_description(_ ev:nostr.Event, inv_desc:LightningInvoiceDescription) -> String? {
	switch inv_desc {
	case .string(let string):
		return string
	case .hash(let deschash):
		guard let desc = event_tag(ev, name: "description") else {
			return nil
		}
		guard let data = desc.data(using: .utf8) else {
			return nil
		}
		guard sha256(data) == deschash else {
			return nil
		}
		
		return desc
	}
}

func invoice_to_zap_invoice(_ invoice:Invoice) -> ZapInvoice? {
	guard case .specific(let amt) = invoice.amount else {
		return nil
	}
	
	return ZapInvoice(description:invoice.description, amount: amt, string: invoice.string, expiry: invoice.expiry, payment_hash: invoice.payment_hash, created_on:invoice.created_on)
}

func preimage_matches_invoice<T>(_ preimage: String, inv: LightningInvoice<T>) -> Bool {
	guard let raw_preimage = hex_decode(preimage) else {
		return false
	}
	
	let hashed = sha256(Data(raw_preimage))
	
	return inv.payment_hash == hashed
}

func determine_zap_target(_ ev:nostr.Event) -> Zap.Target? {
	guard let ptag = event_tag(ev, name: "p") else {
		return nil
	}
	
	if let etag = event_tag(ev, name: "e") {
		return Zap.Target.note(id: etag, author: ptag)
	}
	
	return .profile(ptag)
}
				   
func decode_bolt11(_ s: String) -> Invoice? {
	var bs = blocks()
	bs.num_blocks = 0
	blocks_init(&bs)
	defer {
		blocks_free(&bs)
	}
	let bytes = s.utf8CString
	let _ = bytes.withUnsafeBufferPointer { p in
		damus_parse_content(&bs, p.baseAddress)
	}
	
	guard bs.num_blocks == 1 else {
		return nil
	}
	
	let block = bs.blocks[0]
	
	guard let converted = convert_block(block, tags: []) else {
		return nil
	}
	
	guard case .invoice(let invoice) = converted else {
		return nil
	}
	return invoice
}

func event_tag(_ ev:nostr.Event, name: String) -> String? {
	for tag in ev.tags {
		if case .event = tag.kind {
			return tag.info[0]
		}
	}
	
	return nil
}

func decode_nostr_event_json(_ desc: String) -> nostr.Event? {
	let decoder = JSONDecoder()
	guard let dat = desc.data(using: .utf8) else {
		return nil
	}
	guard let ev = try? decoder.decode(nostr.Event.self, from: dat) else {
		return nil
	}
	
	return ev
}

func decode_zap_request(_ desc: String) -> Zap.Request? {
	let decoder = JSONDecoder()
	guard let jsonData = desc.data(using: .utf8) else {
		return nil
	}
	guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[Any]] else {
		return nil
	}
	
	for array in jsonArray {
		guard array.count == 2 else {
			continue
		}
		let mkey = array.first.flatMap { $0 as? String }
		if let key = mkey, key == "application/nostr" {
			guard let dat = try? JSONSerialization.data(withJSONObject: array[1], options: []) else {
				return nil
			}
			
			guard let zap_req = try? decoder.decode(nostr.Event.self, from: dat) else {
				return nil
			}
			
			guard zap_req.kind == .zap_request else {
				return nil
			}
			
			/// Ensure the signature on the zap request is correct
			guard case .ok = try? zap_req.validate() else {
				return nil
			}
			
			return Zap.Request(ev: zap_req)
		}
	}
	
	return nil
}



func fetch_zapper_from_lnurl(_ lnurl:String) async -> String? {
	guard let endpoint = await fetch_static_payreq(lnurl) else {
		return nil
	}
	
	guard let allows = endpoint.allowsNostr, allows else {
		return nil
	}
	
	guard let key = endpoint.nostrPubkey, key.count == 64 else {
		return nil
	}
	
	return endpoint.nostrPubkey
}

func decode_lnurl(_ lnurl: String) -> URL? {
	guard let decoded = try? bech32_decode(lnurl) else {
		return nil
	}
	guard decoded.hrp == "lnurl" else {
		return nil
	}
	guard let url = URL(string: String(decoding: decoded.data, as: UTF8.self)) else {
		return nil
	}
	return url
}

func fetch_static_payreq(_ lnurl: String) async -> LNUrlPayRequest? {
	guard let url = decode_lnurl(lnurl) else {
		return nil
	}
	
	guard let ret = try? await URLSession.shared.data(from: url) else {
		return nil
	}
	
	let json_str = String(decoding: ret.0, as: UTF8.self)
	
	guard let endpoint: LNUrlPayRequest = decode_json(json_str) else {
		return nil
	}
	
	return endpoint
}

func fetch_zap_invoice(_ payreq: LNUrlPayRequest, zapreq:nostr.Event?, sats: Int, zap_type:Zap.Kind, comment: String?) async -> String? {
	guard var base_url = payreq.callback.flatMap({ URLComponents(string: $0) }) else {
		return nil
	}
	
	let zappable = payreq.allowsNostr ?? false
	let amount: Int64 = Int64(sats) * 1000
	
	var query = [URLQueryItem(name: "amount", value: "\(amount)")]
	
	if let zapreq, zappable && zap_type != .non_zap, let json = encode_json(zapreq) {
		print("zapreq json: \(json)")
		query.append(URLQueryItem(name: "nostr", value: json))
	}
   
	// add a lud12 comment as well if we have it
	if zap_type != .priv, let comment, let limit = payreq.commentAllowed, limit != 0 {
		let limited_comment = String(comment.prefix(limit))
		query.append(URLQueryItem(name: "comment", value: limited_comment))
	}
	
	base_url.queryItems = query
	
	guard let url = base_url.url else {
		return nil
	}
	
	print("url \(url)")
	
	var ret: (Data, URLResponse)? = nil
	do {
		ret = try await URLSession.shared.data(from: url)
	} catch {
		print(error.localizedDescription)
		return nil
	}
	
	guard let ret else {
		return nil
	}
	
	let json_str = String(decoding: ret.0, as: UTF8.self)
	guard let result: LNUrlPayResponse = decode_json(json_str) else {
		print("fetch_zap_invoice error: \(json_str)")
		return nil
	}
	
	return result.pr
}

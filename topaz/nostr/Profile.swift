//
//  Profile.swift
//  topaz
//
//  Created by Tanner Silva on 3/9/23.
//

import Foundation

extension nostr {
	/// Profile is a struct that represents a user's profile on Nostr
	struct Profile:Codable {
		/// name of the profile
		var name:String? = nil
		/// display name of the profile
		var display_name:String? = nil
		/// is the profile deleted?
		var deleted:Bool? = nil
		/// biography of the profile
		var about:String? = nil
		/// profile picture
		var picture:String? = nil
		/// profile banner photo
		var banner:String? = nil
		/// website url of the profile
		var website:String? = nil
		/// lnurl-pay address
		var lud06:String? = nil
		/// lnurl-pay address
		var lud16:String? = nil
		/// nip05 verification address
		var nip05:String? = nil
		/// wallets associated with the profile
		var wallets:[String:String]? = nil
		
		var website_url:URL? {
			return self.website.flatMap { URL(string: $0) }
		}
		
		var lnurl: String? {
			guard let addr = lud16 ?? lud06 else {
				return nil;
			}
			
			if addr.contains("@") {
				return lnaddress_to_lnurl(addr);
			}
			
			if !addr.lowercased().hasPrefix("lnurl") {
				return nil
			}
			
			return addr;
		}
		static func displayName(profile: Profile?, pubkey: String) -> String {
			if pubkey == "anon" {
				return "Anonymous"
			}
			let pk = bech32_nopre_pubkey(pubkey) ?? pubkey
			return profile?.name ?? abbrev_pubkey(pk)
		}
	}
}

func make_ln_url(_ str: String?) -> URL? {
	return str.flatMap { URL(string:"lightning:" + $0) }
}

struct NostrSubscription {
	let sub_id: String
	let filter:nostr.Filter
}

func lnaddress_to_lnurl(_ lnaddr: String) -> String? {
	let parts = lnaddr.split(separator:"@")
	guard parts.count == 2 else {
		return nil
	}
	
	let url = "https://\(parts[1])/.well-known/lnurlp/\(parts[0])";
	guard let dat = url.data(using: .utf8) else {
		return nil
	}
	
	return bech32_encode(hrp: "lnurl", Array(dat))
}

extension nostr.Profile {
	static func makeTestProfile() -> nostr.Profile {
		return nostr.Profile(name: "jb55", display_name: "Will", about: "Its a me", picture: "https://cdn.jb55.com/img/red-me.jpg", banner: "https://pbs.twimg.com/profile_banners/9918032/1531711830/600x200",  website: "jb55.com", lud06: "jb55@jb55.com", lud16: nil, nip05: "jb55@jb55.com")
	}
}

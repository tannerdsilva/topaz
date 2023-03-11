//
//  Keys.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import Foundation
import secp256k1
import Ctopaz

let PUBKEY_HRP = "npub"
let PRIVKEY_HRP = "nsec"

struct KeyPair {
	enum Error:Swift.Error {
		case invalidError
	}
	let pubkey:String
	let privkey:String
	
	init(nsec:String) throws {
		
	}
	func pubkey_bech32() -> String {
		return bech32_pubkey(pubkey)!
	}
	
	func privkey_bech32() -> String {
		return bech32_privkey(privkey) ?? pubkey
	}
}

enum Bech32Key {
	case pub(String)
	case sec(String)
}

enum ParsedKey:Equatable {
	case pub(String)
	case priv(String)
	case hex(String)
	case nip05(String)

	var is_pub: Bool {
		if case .pub = self {
			return true
		}

		if case .nip05 = self {
			return true
		}
		return false
	}

	var is_hex: Bool {
		if case .hex = self {
			return true
		}
		return false
	}
	
	static func == (lhs:ParsedKey, rhs:ParsedKey) -> Bool {
		switch (lhs, rhs) {
			case (.pub(let l), .pub(let r)):
				return l == r
			case (.priv(let l), .priv(let r)):
				return l == r
			case (.hex(let l), .hex(let r)):
				return l == r
			case (.nip05(let l), .nip05(let r)):
				return l == r
			default:
				return false
		}
	}
}

func abbrev_pubkey(_ pubkey: String, amount: Int = 8) -> String {
	return pubkey.prefix(amount) + ":" + pubkey.suffix(amount)
}

func decode_bech32_key(_ key: String) -> Bech32Key? {
	guard let decoded = try? bech32_decode(key) else {
		return nil
	}
	
	let hexed = hex_encode(decoded.data)
	if decoded.hrp == "npub" {
		return .pub(hexed)
	} else if decoded.hrp == "nsec" {
		return .sec(hexed)
	}
	
	return nil
}

func bech32_privkey(_ privkey: String) -> String? {
	guard let bytes = hex_decode(privkey) else {
		return nil
	}
	return bech32_encode(hrp: "nsec", bytes)
}

func bech32_pubkey(_ pubkey: String) -> String? {
	guard let bytes = hex_decode(pubkey) else {
		return nil
	}
	return bech32_encode(hrp: "npub", bytes)
}

func bech32_nopre_pubkey(_ pubkey: String) -> String? {
	guard let bytes = hex_decode(pubkey) else {
		return nil
	}
	return bech32_encode(hrp: "", bytes)
}

func bech32_note_id(_ evid: String) -> String? {
	guard let bytes = hex_decode(evid) else {
		return nil
	}
	return bech32_encode(hrp: "note", bytes)
}

func generate_new_keypair() -> KeyPair {
	let key = try! secp256k1.Signing.PrivateKey()
	let privkey = hex_encode(key.rawRepresentation)
	let pubkey = hex_encode(Data(key.publicKey.xonly.bytes))
	return KeyPair(pubkey:pubkey, privkey:privkey)
}

func privkey_to_pubkey(privkey: String) -> String? {
	guard let sec = hex_decode(privkey) else {
		return nil
	}
	guard let key = try? secp256k1.Signing.PrivateKey(rawRepresentation: sec) else {
		return nil
	}
	return hex_encode(Data(key.publicKey.xonly.bytes))
}

func hexchar(_ val: UInt8) -> UInt8 {
	if val < 10 {
		return 48 + val;
	}
	if val < 16 {
		return 97 + val - 10;
	}
	assertionFailure("impossiburu")
	return 0
}


func hex_encode(_ data: Data) -> String {
	var str = ""
	for c in data {
		let c1 = hexchar(c >> 4)
		let c2 = hexchar(c & 0xF)

		str.append(Character(Unicode.Scalar(c1)))
		str.append(Character(Unicode.Scalar(c2)))
	}
	return str
}



func random_bytes(count: Int) -> Data {
	var bytes = [Int8](repeating: 0, count: count)
	guard
		SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess
	else {
		fatalError("can't copy secure random data")
	}
	return Data(bytes: bytes, count: count)
}

/**
 Detects whether a string might contain an nsec1 prefixed private key.
 It does not determine if it's the current user's private key and does not verify if it is properly encoded or has the right length.
 */
func contentContainsPrivateKey(_ content: String) -> Bool {
	if #available(iOS 16.0, *) {
		return content.contains(/nsec1[02-9ac-z]+/)
	} else {
		let regex = try! NSRegularExpression(pattern: "nsec1[02-9ac-z]+")
		return (regex.firstMatch(in: content, range: NSRange(location: 0, length: content.count)) != nil)
	}

}

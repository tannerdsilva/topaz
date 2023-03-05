//
//  Keys.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import Foundation
import secp256k1
import Vault
import Ctopaz

let PUBKEY_HRP = "npub"
let PRIVKEY_HRP = "nsec"

struct KeyPair {
	let pubkey:String
	let privkey:String
	
	func pubkey_bech32() -> String {
		return bech32_pubkey(pubkey)!
	}
	
	func privkey_bech32() -> String {
		return bech32_privkey(privkey)!
	}
}

struct Keypair {
	let pubkey: String
	let privkey: String?
	let pubkey_bech32: String
	let privkey_bech32: String?
	
	init(pubkey: String, privkey: String?) {
		self.pubkey = pubkey
		self.privkey = privkey
		self.pubkey_bech32 = bech32_pubkey(pubkey) ?? pubkey
		self.privkey_bech32 = privkey.flatMap { bech32_privkey($0) }
	}
}

enum Bech32Key {
	case pub(String)
	case sec(String)
}

struct DamusKeychainConfiguration: KeychainConfiguration {
	var serviceName = "damus"
	var accessGroup: String? = nil
	var accountName = "privkey"
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

func generate_new_keypair() -> Keypair {
	let key = try! secp256k1.Signing.PrivateKey()
	let privkey = hex_encode(key.rawRepresentation)
	let pubkey = hex_encode(Data(key.publicKey.xonly.bytes))
	return Keypair(pubkey: pubkey, privkey: privkey)
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

func save_pubkey(pubkey: String) {
	UserDefaults.standard.set(pubkey, forKey: "pubkey")
}

func save_privkey(privkey: String) throws {
	try Vault.savePrivateKey(privkey, keychainConfiguration: DamusKeychainConfiguration())
}

func clear_saved_privkey() throws {
	try Vault.deletePrivateKey(keychainConfiguration: DamusKeychainConfiguration())
}

func clear_saved_pubkey() {
	UserDefaults.standard.removeObject(forKey: "pubkey")
}

func save_keypair(pubkey: String, privkey: String) throws {
	save_pubkey(pubkey: pubkey)
	try save_privkey(privkey: privkey)
}

func clear_keypair() throws {
	try clear_saved_privkey()
	clear_saved_pubkey()
}

func get_saved_keypair() -> Keypair? {
	do {
		try removePrivateKeyFromUserDefaults()
		
		return get_saved_pubkey().flatMap { pubkey in
			let privkey = get_saved_privkey()
			return Keypair(pubkey: pubkey, privkey: privkey)
		}
	} catch {
		return nil
	}
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
func get_saved_pubkey() -> String? {
	return UserDefaults.standard.string(forKey: "pubkey")
}

func get_saved_privkey() -> String? {
	let mkey = try? Vault.getPrivateKey(keychainConfiguration: DamusKeychainConfiguration());
	return mkey.map { $0.trimmingCharacters(in: .whitespaces) }
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

fileprivate func removePrivateKeyFromUserDefaults() throws {
	guard let privKey = UserDefaults.standard.string(forKey: "privkey") else { return }
	try save_privkey(privkey: privKey)
	UserDefaults.standard.removeObject(forKey: "privkey")
}

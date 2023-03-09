struct Mention {
	enum Kind:String {
		case pubkey = "p"
		case event = "e"
	}
	let index:Int
	let type:Kind
	let ref:ReferenceID
}

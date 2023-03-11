import Foundation
import Ctopaz

extension nostr {
	struct Mention {
		enum Kind:String {
			case pubkey = "p"
			case event = "e"
		}
		let index:Int
		let type:Kind
		let ref:nostr.Reference
	}
}

func render_blocks(blocks: [nostr.Event.Block]) -> String {
	var buildOutput = ""
	for curBlock in blocks {
		switch curBlock {
		case .text(let text):
			buildOutput += text
		case .hashtag(let tag):
			buildOutput += "#\(tag)"
		case .url(let url):
			buildOutput += url.absoluteString
		case .mention(let mention):
			buildOutput += "#[\(mention.index)]"
		case .invoice(let invoice):
			buildOutput += invoice.string
		}
	}
	return buildOutput
}

func parse_textblock(str: String, from: Int, to: Int) -> nostr.Event.Block {
	return .text(String(substring(str, start: from, end: to)))
}

func parse_mentions(content: String, tags: [nostr.Event.Tag]) -> [nostr.Event.Block] {
	var out = [nostr.Event.Block]()
	var bs = blocks()
	bs.num_blocks = 0;
	blocks_init(&bs)
	defer {
		blocks_free(&bs)
	}
	let bytes = content.utf8CString
	let _ = bytes.withUnsafeBufferPointer { p in
		damus_parse_content(&bs, p.baseAddress)
	}
	
	var i = 0
	while (i < bs.num_blocks) {
		let block = bs.blocks[i]
		
		if let converted = convert_block(block, tags: tags.compactMap({ $0.toArray() })) {
			out.append(converted)
		}
		
		i += 1
	}

	return out
}

func strblock_to_string(_ s: str_block_t) -> String? {
	let len = s.end - s.start
	let bytes = Data(bytes: s.start, count: len)
	return String(bytes: bytes, encoding: .utf8)
}

func convert_block(_ b: block_t, tags: [[String]]) -> nostr.Event.Block? {
	if b.type == BLOCK_HASHTAG {
		guard let str = strblock_to_string(b.block.str) else {
			return nil
		}
		return .hashtag(str)
	} else if b.type == BLOCK_TEXT {
		guard let str = strblock_to_string(b.block.str) else {
			return nil
		}
		return .text(str)
	} else if b.type == BLOCK_MENTION {
		return convert_mention_block(ind: b.block.mention, tags: tags)
	} else if b.type == BLOCK_URL {
		return convert_url_block(b.block.str)
	} else if b.type == BLOCK_INVOICE {
		return convert_invoice_block(b.block.invoice)
	}
	
	return nil
}

func convert_url_block(_ b: str_block) -> nostr.Event.Block? {
	guard let str = strblock_to_string(b) else {
		return nil
	}
	guard let url = URL(string: str) else {
		return .text(str)
	}
	return .url(url)
}

func maybe_pointee<T>(_ p: UnsafeMutablePointer<T>!) -> T? {
	guard p != nil else {
		return nil
	}
	return p.pointee
}

func format_actions_abbrev(_ actions: Int) -> String {
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	formatter.positiveSuffix = "m"
	formatter.positivePrefix = ""
	formatter.minimumFractionDigits = 0
	formatter.maximumFractionDigits = 3
	formatter.roundingMode = .down
	formatter.roundingIncrement = 0.1
	formatter.multiplier = 1
		
	if actions >= 1_000_000 {
		formatter.positiveSuffix = "m"
		formatter.multiplier = 0.000001
	} else if actions >= 1000 {
		formatter.positiveSuffix = "k"
		formatter.multiplier = 0.001
	} else {
		return "\(actions)"
	}
	
	let actions = NSNumber(value: actions)
	
	return formatter.string(from: actions) ?? "\(actions)"
}

func format_msats_abbrev(_ msats: Int64) -> String {
	let formatter = NumberFormatter()
	formatter.numberStyle = .decimal
	formatter.positiveSuffix = "m"
	formatter.positivePrefix = ""
	formatter.minimumFractionDigits = 0
	formatter.maximumFractionDigits = 3
	formatter.roundingMode = .down
	formatter.roundingIncrement = 0.1
	formatter.multiplier = 1
	
	let sats = NSNumber(value: (Double(msats) / 1000.0))
	
	if msats >= 1_000_000*1000 {
		formatter.positiveSuffix = "m"
		formatter.multiplier = 0.000001
	} else if msats >= 1000*1000 {
		formatter.positiveSuffix = "k"
		formatter.multiplier = 0.001
	} else {
		return sats.stringValue
	}
	
	return formatter.string(from: sats) ?? sats.stringValue
}

func format_msats(_ msat: Int64, locale: Locale = Locale.current) -> String {
	let numberFormatter = NumberFormatter()
	numberFormatter.numberStyle = .decimal
	numberFormatter.minimumFractionDigits = 0
	numberFormatter.maximumFractionDigits = 3
	numberFormatter.roundingMode = .down
	numberFormatter.locale = locale

	let sats = NSNumber(value: (Double(msat) / 1000.0))
	let formattedSats = numberFormatter.string(from: sats) ?? sats.stringValue

	let bundle = bundleForLocale(locale: locale)
	return String(format: bundle.localizedString(forKey: "sats_count", value: nil, table: nil), locale: locale, sats.decimalValue as NSDecimalNumber, formattedSats)
}

func convert_invoice_block(_ b: invoice_block) -> nostr.Event.Block? {
	guard let invstr = strblock_to_string(b.invstr) else {
		return nil
	}
	
	guard var b11 = maybe_pointee(b.bolt11) else {
		return nil
	}
	
	guard let description = convert_invoice_description(b11: b11) else {
		return nil
	}
	
	let amount: Amount = maybe_pointee(b11.msat).map { .specific(Int64($0.millisatoshis)) } ?? .any
	let payment_hash = Data(bytes: &b11.payment_hash, count: 32)
	let created_at = b11.timestamp
	
	tal_free(b.bolt11)
	return .invoice(Invoice(description: description, amount: amount, string: invstr, expiry: b11.expiry, payment_hash: payment_hash, created_at: created_at))
}

func convert_invoice_description(b11: bolt11) -> InvoiceDescription? {
	if let desc = b11.description {
		return .description(String(cString: desc))
	}
	
	if var deschash = maybe_pointee(b11.description_hash) {
		return .description_hash(Data(bytes: &deschash, count: 32))
	}
	
	return nil
}

func convert_mention_block(ind: Int32, tags: [[String]]) -> nostr.Event.Block?
{
	let ind = Int(ind)
	
	if ind < 0 || (ind + 1 > tags.count) || tags[ind].count < 2 {
		return .text("#[\(ind)]")
	}
		
	let tag = tags[ind]
	guard let mention_type = parse_mention_type(tag[0]) else {
		return .text("#[\(ind)]")
	}
	
	guard let ref = tag_to_refid(tag) else {
		return .text("#[\(ind)]")
	}
	
	return .mention(nostr.Mention(index: ind, type: mention_type, ref: ref))
}

func parse_mentions_old(content: String, tags: [[String]]) -> [nostr.Event.Block] {
	let p = Parser(pos: 0, str: content)
	var blocks: [nostr.Event.Block] = []
	var starting_from: Int = 0
	
	while p.pos < content.count {
		if !consume_until(p, match: { !$0.isWhitespace}) {
			break
		}
		
		let pre_mention = p.pos
		
		let c = peek_char(p, 0)
		let pr = peek_char(p, -1)
		
		if c == "#" {
			if let mention = parse_mention(p, tags: tags) {
				blocks.append(parse_textblock(str: p.str, from: starting_from, to: pre_mention))
				blocks.append(.mention(mention))
				starting_from = p.pos
			} else if let hashtag = parse_hashtag(p) {
				blocks.append(parse_textblock(str: p.str, from: starting_from, to: pre_mention))
				blocks.append(.hashtag(hashtag))
				starting_from = p.pos
			} else {
				if !consume_until(p, match: { $0.isWhitespace }) {
					break
				}
			}
		} else if c == "h" && (pr == nil || pr!.isWhitespace) {
			if let url = parse_url(p) {
				blocks.append(parse_textblock(str: p.str, from: starting_from, to: pre_mention))
				blocks.append(.url(url))
				starting_from = p.pos
			} else {
				if !consume_until(p, match: { $0.isWhitespace }) {
					break
				}
			}
		} else {
			if !consume_until(p, match: { $0.isWhitespace }) {
				break
			}
		}
	}
	
	if p.str.count - starting_from > 0 {
		blocks.append(parse_textblock(str: p.str, from: starting_from, to: p.str.count))
	}
	
	return blocks
}

func parse_while(_ p: Parser, match: (Character) -> Bool) -> String? {
	var i: Int = 0
	let sub = substring(p.str, start: p.pos, end: p.str.count)
	let start = p.pos
	for c in sub {
		if match(c) {
			p.pos += 1
		} else {
			break
		}
		i += 1
	}
	
	let end = start + i
	if start == end {
		return nil
	}
	return String(substring(p.str, start: start, end: end))
}

func is_hashtag_char(_ c: Character) -> Bool {
	return c.isLetter || c.isNumber
}

func prev_char(_ p: Parser, n: Int) -> Character? {
	if p.pos - n < 0 {
		return nil
	}
	
	let ind = p.str.index(p.str.startIndex, offsetBy: p.pos - n)
	return p.str[ind]
}

func is_punctuation(_ c: Character) -> Bool {
	return c.isWhitespace || c.isPunctuation
}

func parse_url(_ p: Parser) -> URL? {
	let start = p.pos
	
	if !parse_str(p, "http") {
		return nil
	}
	
	if parse_char(p, "s") {
		if !parse_str(p, "://") {
			return nil
		}
	} else {
		if !parse_str(p, "://") {
			return nil
		}
	}
	
	if !consume_until(p, match: { c in c.isWhitespace }, end_ok: true) {
		p.pos = start
		return nil
	}
	
	let url_str = String(substring(p.str, start: start, end: p.pos))
	guard let url = URL(string: url_str) else {
		p.pos = start
		return nil
	}
	
	return url
}

func parse_hashtag(_ p: Parser) -> String? {
	let start = p.pos
	
	if !parse_char(p, "#") {
		return nil
	}
	
	if let prev = prev_char(p, n: 2) {
		// we don't allow adjacent hashtags
		if !is_punctuation(prev) {
			return nil
		}
	}
	
	guard let str = parse_while(p, match: is_hashtag_char) else {
		p.pos = start
		return nil
	}
	
	return str
}

func parse_mention(_ p: Parser, tags: [[String]]) -> nostr.Mention? {
	let start = p.pos
	
	if !parse_str(p, "#[") {
		return nil
	}
	
	guard let digit = parse_digit(p) else {
		p.pos = start
		return nil
	}
	
	var ind = digit
	
	if let d2 = parse_digit(p) {
		ind = digit * 10
		ind += d2
	}
	
	if !parse_char(p, "]") {
		return nil
	}
	
	var kind:nostr.Mention.Kind = .pubkey
	if ind > tags.count - 1 {
		return nil
	}
	
	if tags[ind].count == 0 {
		return nil
	}
	
	switch tags[ind][0] {
	case "e": kind = .event
	case "p": kind = .pubkey
	default: return nil
	}
	
	guard let ref = tags[ind].toReference() else {
		return nil
	}
	
	return nostr.Mention(index: ind, type: kind, ref: ref)
}

func find_tag_ref(type: String, id: String, tags: [[String]]) -> Int? {
	var i: Int = 0
	for tag in tags {
		if tag.count >= 2 {
			if tag[0] == type && tag[1] == id {
				return i
			}
		}
		i += 1
	}
	
	return nil
}

struct PostTags {
	let blocks: [nostr.Event.Block]
	let tags: [[String]]
}

func parse_mention_type(_ c: String) -> nostr.Mention.Kind? {
	if c == "e" {
		return .event
	} else if c == "p" {
		return .pubkey
	}
	
	return nil
}

/// Convert
func make_post_tags(post_blocks: [PostBlock], tags: [[String]]) -> PostTags {
	var new_tags = tags
	var blocks: [nostr.Event.Block] = []
	
	for post_block in post_blocks {
		switch post_block {
		case .ref(let ref):
			guard let mention_type = parse_mention_type(ref.key) else {
				continue
			}
			if let ind = find_tag_ref(type: ref.key, id: ref.ref_id, tags: tags) {
				let mention = nostr.Mention(index: ind, type: mention_type, ref: ref)
				let block = nostr.Event.Block.mention(mention)
				blocks.append(block)
			} else {
				let ind = new_tags.count
				new_tags.append(try! ref.toTag().toArray())
				let mention = nostr.Mention(index: ind, type: mention_type, ref: ref)
				let block = nostr.Event.Block.mention(mention)
				blocks.append(block)
			}
		case .hashtag(let hashtag):
			new_tags.append(["t", hashtag.lowercased()])
			blocks.append(.hashtag(hashtag))
		case .text(let txt):
			blocks.append(nostr.Event.Block.text(txt))
		}
	}
	
	return PostTags(blocks: blocks, tags: new_tags)
}

//
//  Extension.swift
//  SwiftNats
//
//  Created by kakilangit on 1/21/16.
//  Copyright © 2016 Travelish. All rights reserved.
//

extension NSData {
	func toString() -> String? {
		return NSString(data: self, encoding: NSUTF8StringEncoding) as String?
	}
}

extension NSInputStream {
	func readStream() -> NSData? {
		let max_buffer = 4096
		var dataQueue = [NSData]()
		var length = max_buffer
		let buf = NSMutableData(capacity: max_buffer)
		let buffer = UnsafeMutablePointer<UInt8>(buf!.bytes)

		// read stream per max_buffer
		while length > 0 {
			length = self.read(buffer, maxLength: max_buffer)
			guard length > 0 else { break }
			dataQueue.append(NSData(bytes: buffer, length: length))
			if length < max_buffer { break }
		}

		guard !dataQueue.isEmpty else { return nil }

		let data = dataQueue.reduce(NSData(), combine: {
			let combined = NSMutableData(data: $0)
			combined.appendData($1)
			return combined
		})

		// print("readStream \(data.toString())")

		return data
	}

	func readStreamLoop() -> String? {
		while (true) {
			if self.hasBytesAvailable {
				return self.readStream()?.toString()
			}
			if (self.streamError != nil) { break }
		}

		return nil
	}
}

extension NSOutputStream {
	func writeStream(data: NSData) {
		let bytes = UnsafePointer<UInt8>(data.bytes)
		_ = self.write(bytes, maxLength: data.length)

		// print("writeStream \(data.toString())")
	}

	func writeStreamLoop(data: NSData) {
		while (true) {
			if self.hasSpaceAvailable {
				self.writeStream(data)
				break
			}
			if self.streamError != nil { break }
		}
	}
}

extension String
{
	func flattenedMessage() -> String {
		let components = self.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet())

		return components.filter({ $0 != NSCharacterSet.newlineCharacterSet() }).reduce("", combine: { $0 + $1 })
	}

	func removePrefix(prefix: String, _ adder: Int = 0) -> String {
		let start = prefix.characters.count - 1 + adder
		let minus = -1
		guard start > minus && start < self.characters.count else { return self }

		let range = Range(start: prefix.startIndex.advancedBy(start), end: self.endIndex)

		return self.substringWithRange(range)
	}

	func convertToDictionary() -> [String: AnyObject]? {
		if let data = self.dataUsingEncoding(NSUTF8StringEncoding) {
			do {
				return try NSJSONSerialization.JSONObjectWithData(data, options: []) as? [String: AnyObject]
			} catch let error as NSError {
				print(error)
			}
		}
		return nil
	}

	static func randomize(prefix: String = "", length: Int = 0) -> String {

		let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".characters
		let lettersLength = UInt32(letters.count)

		let randomCharacters = (0..<length).map { i -> String in
			let offset = Int(arc4random_uniform(lettersLength))
			let c = letters[letters.startIndex.advancedBy(offset)]
			return String(c)
		}

		return prefix + randomCharacters.joinWithSeparator("")
	}
}

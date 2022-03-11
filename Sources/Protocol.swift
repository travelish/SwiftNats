//
//  NatsStreamDelegate.swift
//  SwiftNats
//
//  Created by kakilangit on 1/21/16.
//  Copyright © 2016 Travelish. All rights reserved.
//

import Foundation

public protocol NatsDelegate: class {
	func natsDidConnect(nats: Nats)
	func natsDidDisconnect(nats: Nats, error: NSError?)
	func natsDidReceiveMessage(nats: Nats, msg: NatsMessage)
	func natsDidReceivePing(nats: Nats)
}

public struct NatsSubscription {
	public let id: String
	public let subject: String
	public let queueGroup: String
	fileprivate(set) var count: UInt

	func sub() -> String {
		let group: () -> String = {
			if self.queueGroup.count > 0 {
				return "\(self.queueGroup) "
			}
			return self.queueGroup
		}

		return "\(Proto.SUB.rawValue) \(subject) \(group())\(id)\r\n"
	}

	func unsub(_ max: UInt32) -> String {
		let wait: () -> String = {
			if max > 0 {
				return " \(max)"
			}
			return ""
		}
		return "\(Proto.UNSUB.rawValue) \(id)\(String(describing: wait))\r\n"
	}

	mutating func counter() {
		self.count += 1
	}
}

public struct NatsMessage {
	let subject: String
	let count: UInt
	var reply: String?
	var payload: String?
}

internal enum Proto: String {
	case CONNECT = "CONNECT"
	case SUB = "SUB"
	case UNSUB = "UNSUB"
	case PUB = "PUB"
	case MSG = "MSG"
	case INFO = "INFO"
	case OK = "+OK"
	case ERR = "-ERR"
	case PONG = "PONG"
	case PING = "PING"
}

internal struct Server {
	let serverId: String
	let version: String
	let go: String
	let host: String
	let port: UInt
	let authRequired: Bool
	let sslRequired: Bool
	let maxPayload: UInt

	init(data: [String: AnyObject]) {
		self.serverId = data["server_id"] as! String
		self.version = data["version"] as! String
		self.go = data["go"] as! String
		self.host = data["host"] as! String
		self.port = data["port"] as! UInt
		self.authRequired = data["auth_required"] as! Bool
		
		if data["ssl_required"] != nil {
			self.sslRequired = data["ssl_required"] as! Bool
		} else {
			self.sslRequired = false
		}
		
		self.maxPayload = data["max_payload"] as! UInt
	}
}

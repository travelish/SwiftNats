//
//  Connection.swift
//  SwiftNats
//
//  Created by kakilangit on 1/21/16.
//  Copyright © 2016 Travelish. All rights reserved.
//
//  http://nats.io/documentation/internals/nats-protocol/

import Foundation

public class Nats: NSObject, NSStreamDelegate {
	public var queue = dispatch_get_main_queue()
	public weak var delegate: NatsDelegate?

	let version = "0.0.1"
	let lang = "swift"
	let name = "SwiftNats"
	let MaxFrameSize: Int = 32

	private var server: Server?
	private var subscriptions = [NatsSubscription]()

	private var id: String?
	private var outputStream: NSOutputStream?
	private var inputStream: NSInputStream?
	private var writeQueue = NSOperationQueue()
	private var connected: Bool = false
	private var counter: UInt32 = 0

	private var url: NSURL!
	private var verbose: Bool = true
	private var pedantic: Bool = false

	private var isRunLoop: Bool = false

	public var connectionId: String? {
		return id
	}

	public var isConnected: Bool {
		return connected
	}

	/**
	 * ================
	 * Public Functions
	 * ================
	 */

	public init(url: String, verbose: Bool = true, pedantic: Bool = false) {
		self.url = NSURL(string: url)!
		self.verbose = verbose
		self.pedantic = pedantic

		writeQueue.maxConcurrentOperationCount = 1
	}

	public func option(url: String, verbose: Bool = true, pedantic: Bool = false) {
		self.url = NSURL(string: url)!
		self.verbose = verbose
		self.pedantic = pedantic
	}

	/**
	 * connect() -> Void
	 * make connection
	 *
	 */
	public func connect() {
		self.open()

		guard let newReadStream = inputStream, newWriteStream = outputStream else { return }
		guard isConnected else { return }

		for stream in [newReadStream, newWriteStream] {
			stream.delegate = self
			stream.scheduleInRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
		}

		// NSRunLoop
		NSRunLoop.currentRunLoop().runMode(NSDefaultRunLoopMode, beforeDate: NSDate.distantFuture() as NSDate)
	}

	/**
	 * reconnect() -> Void
	 * make connection
	 *
	 */
	public func reconnect(url: String, verbose: Bool = true, pedantic: Bool = false) {
		self.option(url, verbose: verbose, pedantic: pedantic)
		guard !isConnected else {
			didDisconnect(nil)
			self.reconnect(url, verbose: verbose, pedantic: pedantic)
			return
		}

		self.connect()
	}

	/**
	 * disconnect() -> Void
	 * close connection
	 *
	 */
	public func disconnect() {
		didDisconnect(nil)
	}

	/**
	 * subscribe(subject: String, queueGroup: String = "") -> Void
	 * subscribe to subject
	 *
	 */
	public func subscribe(subject: String, queueGroup: String = "") -> NatsSubscription? {
		guard subscriptions.filter({ $0.subject == subject }).count == 0 else { return nil }

		let sub = NatsSubscription(id: String.randomize("SUB_", length: 10), subject: subject, queueGroup: queueGroup, count: 0)

		subscriptions.append(sub)
		sendText(sub.sub())

		return sub
	}

	/**
	 * unsubscribe(subject: String) -> Void
	 * unsubscribe from subject
	 *
	 */
	public func unsubscribe(subject: String, max: UInt32 = 0) {
		guard let sub = subscriptions.filter({ $0.subject == subject }).first else { return }

		subscriptions = subscriptions.filter({ $0.id != sub.id })
		sendText(sub.unsub(max))
	}

	/**
	 * publish(subject: String) -> Void
	 * publish to subject
	 *
	 */
	public func publish(subject: String, payload: String) {
		let pub: () -> String = {
			if let data = payload.dataUsingEncoding(NSUTF8StringEncoding) {
				return "\(Proto.PUB.rawValue) \(subject) \(data.length)\r\n\(payload)\r\n"
			}
			return ""
		}
		sendText(pub())
	}

	/**
	 * reply(subject: String, replyto: String, payload: String)  -> Void
	 * reply to id in subject
	 *
	 */
	public func reply(subject: String, replyto: String, payload: String) {
		let response: () -> String = {
			if let data = payload.dataUsingEncoding(NSUTF8StringEncoding) {
				return "\(Proto.PUB.rawValue) \(subject) \(replyto) \(data.length)\r\n\(payload)\r\n"
			}
			return ""
		}
		sendText(response())
	}

	// NSStreamDelegate
	public func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
		switch aStream {

		case inputStream!:
			switch eventCode {
			case [.HasBytesAvailable]:
				if let string = inputStream?.readStream()?.toString() {
					dispatchInputStream(string)
				}
				break
			case [.ErrorOccurred]:
				didDisconnect(inputStream?.streamError)
				break
			case [.EndEncountered]:
				didDisconnect(inputStream?.streamError)
				break
			default:
				break
			}
		default:
			break
		}
	}

	/**
	 * =================
	 * Private Functions
	 * =================
	 */

	/*
	 * open() -> Void
	 * open stream connection
	 * set server
	 * blocking, read & write stream in loop
	 *
	 */
	private func open() {
		guard !isConnected else { return }
		guard let host = url.host, let port = url.port else { return }

		var readStream: Unmanaged<CFReadStream>?
		var writeStream: Unmanaged<CFWriteStream>?

		CFStreamCreatePairWithSocketToHost(nil, host, UInt32(port.unsignedIntValue), &readStream, &writeStream) // -> send
		inputStream = readStream!.takeRetainedValue()
		outputStream = writeStream!.takeRetainedValue()

		guard let inStream = inputStream, let outStream = outputStream else { return }

		inStream.open()
		outStream.open()

		if let info = inStream.readStreamLoop() { // <- receive
			if info.hasPrefix(Proto.INFO.rawValue) {
				if let config = info.flattenedMessage().removePrefix(Proto.INFO.rawValue, 1).convertToDictionary() {
					self.server = Server(data: config)
					self.authorize(outStream, inStream)
				}
			}
		}
	}

	/**
	 * authorize(outStream: NSOutputStream, _ inStream: NSInputStream) -> Void
	 * blocking, read & write stream in loop
	 *
	 */
	private func authorize(outStream: NSOutputStream, _ inStream: NSInputStream) {
		guard let user = self.url?.user, let password = self.url?.password, let srv = self.server else { return }

		if !srv.authRequired {
			didConnect()
			return
		}

		let config = [
			"verbose": self.verbose,
			"pedantic": self.pedantic,
			"ssl_required": srv.sslRequired,
			"name": self.name,
			"lang": self.lang,
			"version": self.version,
			"user": user,
			"pass": password
		]

		do {
			let configData = try NSJSONSerialization.dataWithJSONObject(config, options: [])
			if let configString = configData.toString() {
				if let data = "\(Proto.CONNECT.rawValue) \(configString)\r\n".dataUsingEncoding(NSUTF8StringEncoding) {

					outStream.writeStreamLoop(data) // -> send
					if let info = inStream.readStreamLoop() { // <- receive
						if info.hasPrefix(Proto.ERR.rawValue) {
							let err = info.removePrefix(Proto.ERR.rawValue, 1)
							didDisconnect(NSError(domain: NSURLErrorDomain, code: 404, userInfo: [NSLocalizedDescriptionKey: err]))
						} else {
							didConnect()
						}
					}
				}
			}
		} catch let error as NSError {
			didDisconnect(error)
		}
	}

	/**
	 * didConnect() -> Void
	 * set self.connection state
	 * delegate didConnect
	 * non blocking
	 *
	 */
	private func didConnect() {
		self.id = String.randomize("CONN_", length: 10)
		self.connected = true
		dispatch_async(queue) { [weak self] in
			guard let s = self else { return }
			s.delegate?.natsDidConnect(s)
		}
	}

	/**
	 * didDisconnect() -> Void
	 * set self.connection state
	 * delegate didDisconnect
	 * non blocking
	 *
	 */
	private func didDisconnect(err: NSError?) {
		self.connected = false
		dispatch_async(queue) { [weak self] in
			guard let s = self else { return }
			guard let newReadStream = s.inputStream, newWriteStream = s.outputStream else { return }

			for stream in [newReadStream, newWriteStream] {
				stream.delegate = nil
				stream.removeFromRunLoop(NSRunLoop.currentRunLoop(), forMode: NSDefaultRunLoopMode)
				stream.close()
			}

			s.delegate?.natsDidDisconnect(s, error: err)
		}
	}

	/**
	 * sendData(data: NSData) -> Void
	 * write data to output stream
	 *
	 */
	private func sendData(data: NSData) {
		guard isConnected else { return }

		writeQueue.addOperationWithBlock { [weak self] in
			guard let s = self else { return }
			guard let stream = s.outputStream else { return }

			stream.writeStreamLoop(data)
		}
	}

	/**
	 * sendText(text: String) -> Void
	 * write string to output stream
	 *
	 */
	private func sendText(text: String) {
		if let data = text.dataUsingEncoding(NSUTF8StringEncoding) {
			sendData(data)
		}
	}

	/**
	 * dispatchInputStream(msg: String) -> Void
	 * routing received message from NSStreamDelegate
	 *
	 */
	private func dispatchInputStream(msg: String) {
		if msg.hasPrefix(Proto.PING.rawValue) {
			processPing()
		} else if msg.hasPrefix(Proto.OK.rawValue) {
			processOk(msg)
		} else if msg.hasPrefix(Proto.ERR.rawValue) {
			processErr(msg.removePrefix(Proto.ERR.rawValue, 1))
		} else if msg.hasPrefix(Proto.MSG.rawValue) {
			processMessage(msg)
		}
	}

	/**
	 * processMessage(msg: String) -> Void
	 * processMessage
	 *
	 */
	private func processMessage(msg: String) {
		let components = msg.componentsSeparatedByCharactersInSet(NSCharacterSet.newlineCharacterSet()).filter { !$0.isEmpty }

		guard components.count > 0 else { return }

		let header = components[0].removePrefix(Proto.MSG.rawValue, 1).componentsSeparatedByCharactersInSet(NSCharacterSet.whitespaceCharacterSet()).filter { !$0.isEmpty }

		let subject = header[0]
		// let sid = UInt32(header[1])
		// var byte = UInt32(header[2])

		var payload: String?
		var reply: String?

		if components.count == 2 {
			payload = components[1]
		}

		if header.count > 3 {
			reply = header[2]
			// byte = UInt32(header[3])
		}

		var sub = subscriptions.filter({ $0.subject == subject }).first

		guard sub != nil else { return }

		sub!.counter()

		subscriptions = subscriptions.filter({ $0.subject != sub!.subject })
		subscriptions.append(sub!)

		let message = NatsMessage(subject: sub!.subject, count: sub!.count, reply: reply, payload: payload)

		dispatch_async(queue) { [weak self] in
			guard let s = self else { return }
			s.delegate?.natsDidReceiveMessage(s, msg: message)
		}
	}

	/**
	 * processOk(msg: String) -> Void
	 * +OK
	 *
	 */
	private func processOk(msg: String) {
		print("processOk \(msg)")
	}

	/**
	 * processErr(msg: String) -> Void
	 * -ERR
	 *
	 */
	private func processErr(msg: String) {
		print("processErr \(msg)")
	}

	/**
	 * processPing() -> Void
	 * PING keep-alive message
	 * PONG keep-alive response
	 *
	 */
	private func processPing() {
		sendText(Proto.PONG.rawValue)
	}
}
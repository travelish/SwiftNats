//
//  Connection.swift
//  SwiftNats
//
//  Created by kakilangit on 1/21/16.
//  Copyright © 2016 Travelish. All rights reserved.
//
//  http://nats.io/documentation/internals/nats-protocol/

import Foundation

open class Nats: NSObject, StreamDelegate {
	open var queue = DispatchQueue.main
	open weak var delegate: NatsDelegate?

	let version = "3.0.0-alpha.1"
	let lang = "swift"
	let name = "SwiftNats"
	let MaxFrameSize: Int = 32

	fileprivate var server: Server?
	fileprivate var subscriptions = [NatsSubscription]()

	fileprivate var id: String?
	fileprivate var outputStream: OutputStream?
	fileprivate var inputStream: InputStream?
	fileprivate var writeQueue = OperationQueue()
	fileprivate var connected: Bool = false
	fileprivate var counter: UInt32 = 0

	fileprivate var url: URL!
	fileprivate var verbose: Bool = true
	fileprivate var pedantic: Bool = false

	fileprivate var isRunLoop: Bool = false

	open var connectionId: String? {
		return id
	}

	open var isConnected: Bool {
		return connected
	}

	/**
	 * ================
	 * Public Functions
	 * ================
	 */

	public init(url: String, verbose: Bool = true, pedantic: Bool = false) {
		self.url = URL(string: url)!
		self.verbose = verbose
		self.pedantic = pedantic

		writeQueue.maxConcurrentOperationCount = 1
	}

	open func option(_ url: String, verbose: Bool = true, pedantic: Bool = false) {
		self.url = URL(string: url)!
		self.verbose = verbose
		self.pedantic = pedantic
	}

	/**
	 * connect() -> Void
	 * make connection
	 *
	 */
	open func connect() {
		self.open()

		guard let newReadStream = inputStream, let newWriteStream = outputStream else { return }
		guard isConnected else { return }

		for stream in [newReadStream, newWriteStream] {
			stream.delegate = self
			stream.schedule(in: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
		}

		// NSRunLoop
		RunLoop.current.run(mode: RunLoopMode.defaultRunLoopMode, before: Date.distantFuture as Date)
	}

	/**
	 * reconnect() -> Void
	 * make connection
	 *
	 */
	open func reconnect(_ url: String, verbose: Bool = true, pedantic: Bool = false) {
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
	open func disconnect() {
		didDisconnect(nil)
	}

	/**
	 * subscribe(subject: String, queueGroup: String = "") -> Void
	 * subscribe to subject
	 *
	 */
	open func subscribe(_ subject: String, queueGroup: String = "") -> Void {
		guard subscriptions.filter({ $0.subject == subject }).count == 0 else { return }

		let sub = NatsSubscription(id: String.randomize("SUB_", length: 10), subject: subject, queueGroup: queueGroup, count: 0)

		subscriptions.append(sub)
		sendText(sub.sub())
	}

	/**
	 * unsubscribe(subject: String) -> Void
	 * unsubscribe from subject
	 *
	 */
	open func unsubscribe(_ subject: String, max: UInt32 = 0) {
		guard let sub = subscriptions.filter({ $0.subject == subject }).first else { return }

		subscriptions = subscriptions.filter({ $0.id != sub.id })
		sendText(sub.unsub(max))
	}

	/**
	 * publish(subject: String) -> Void
	 * publish to subject
	 *
	 */
	open func publish(_ subject: String, payload: String) {
		let pub: () -> String = {
			if let data = payload.data(using: String.Encoding.utf8) {
				return "\(Proto.PUB.rawValue) \(subject) \(data.count)\r\n\(payload)\r\n"
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
	open func reply(_ subject: String, replyto: String, payload: String) {
		let response: () -> String = {
			if let data = payload.data(using: String.Encoding.utf8) {
				return "\(Proto.PUB.rawValue) \(subject) \(replyto) \(data.count)\r\n\(payload)\r\n"
			}
			return ""
		}
		sendText(response())
	}

	// NSStreamDelegate
	open func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
		switch aStream {

		case inputStream!:
			switch eventCode {
			case [.hasBytesAvailable]:
				if let string = inputStream?.readStream()?.toString() {
					dispatchInputStream(string)
				}
				break
			case [.errorOccurred]:
				didDisconnect(inputStream?.streamError as NSError?)
				break
			case [.endEncountered]:
				didDisconnect(inputStream?.streamError as NSError?)
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
	fileprivate func open() {
		guard !isConnected else { return }
		guard let host = url.host, let port = url.port else { return }

		var readStream: Unmanaged<CFReadStream>?
		var writeStream: Unmanaged<CFWriteStream>?

		CFStreamCreatePairWithSocketToHost(nil, host as CFString!, UInt32(port), &readStream, &writeStream) // -> send
		inputStream = readStream!.takeRetainedValue()
		outputStream = writeStream!.takeRetainedValue()

		guard let inStream = inputStream, let outStream = outputStream else { return }

		inStream.open()
		outStream.open()

		if let info = inStream.readStreamLoop() { // <- receive
			if info.hasPrefix(Proto.INFO.rawValue) {
                if let config = info.flattenedMessage().removePrefix(Proto.INFO.rawValue).convertToDictionary() {
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
	fileprivate func authorize(_ outStream: OutputStream, _ inStream: InputStream) {
		do {
			guard let srv = self.server else {
				throw NSError(domain: NSURLErrorDomain, code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid Server"])
			}

			if !srv.authRequired {
				didConnect()
				return
			}

			guard let user = self.url?.user, let password = self.url?.password else {
				throw NSError(domain: NSURLErrorDomain, code: 400, userInfo: [NSLocalizedDescriptionKey: "User/Password Required"])
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
			] as [String : Any]

			let configData = try JSONSerialization.data(withJSONObject: config, options: [])
			if let configString = configData.toString() {
				if let data = "\(Proto.CONNECT.rawValue) \(configString)\r\n".data(using: String.Encoding.utf8) {

					outStream.writeStreamLoop(data) // -> send
					if let info = inStream.readStreamLoop() { // <- receive
						if info.hasPrefix(Proto.ERR.rawValue) {
							let err = info.removePrefix(Proto.ERR.rawValue)
							didDisconnect(NSError(domain: NSURLErrorDomain, code: 400, userInfo: [NSLocalizedDescriptionKey: err]))
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
	fileprivate func didConnect() {
		self.id = String.randomize("CONN_", length: 10)
		self.connected = true
		queue.async { [weak self] in
			guard let s = self else { return }
            s.delegate?.natsDidConnect(nats:s)
		}
	}

	/**
	 * didDisconnect() -> Void
	 * set self.connection state
	 * delegate didDisconnect
	 * non blocking
	 *
	 */
	fileprivate func didDisconnect(_ err: NSError?) {
		self.connected = false
		queue.async { [weak self] in
			guard let s = self else { return }
			guard let newReadStream = s.inputStream, let newWriteStream = s.outputStream else { return }

			for stream in [newReadStream, newWriteStream] {
				stream.delegate = nil
				stream.remove(from: RunLoop.current, forMode: RunLoopMode.defaultRunLoopMode)
				stream.close()
			}

			s.delegate?.natsDidDisconnect(nats:s, error: err)
		}
	}

	/**
	 * sendData(data: NSData) -> Void
	 * write data to output stream
	 *
	 */
	fileprivate func sendData(_ data: Data) {
		guard isConnected else { return }

		writeQueue.addOperation { [weak self] in
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
	fileprivate func sendText(_ text: String) {
		if let data = text.data(using: String.Encoding.utf8) {
			sendData(data)
		}
	}

	/**
	 * dispatchInputStream(msg: String) -> Void
	 * routing received message from NSStreamDelegate
	 *
	 */
	fileprivate func dispatchInputStream(_ msg: String) {
		if msg.hasPrefix(Proto.PING.rawValue) {
			processPing()
		} else if msg.hasPrefix(Proto.OK.rawValue) {
			processOk(msg)
		} else if msg.hasPrefix(Proto.ERR.rawValue) {
			processErr(msg.removePrefix(Proto.ERR.rawValue))
		} else if msg.hasPrefix(Proto.MSG.rawValue) {
			processMessage(msg)
		}
	}

	/**
	 * processMessage(msg: String) -> Void
	 * processMessage
	 *
	 */
	fileprivate func processMessage(_ msg: String) {
		let components = msg.components(separatedBy: CharacterSet.newlines).filter { !$0.isEmpty }

		guard components.count > 0 else { return }

		let header = components[0]
            .removePrefix(Proto.MSG.rawValue)
            .components(separatedBy: CharacterSet.whitespaces)
            .filter { !$0.isEmpty }

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

		queue.async { [weak self] in
			guard let s = self else { return }
			s.delegate?.natsDidReceiveMessage(nats:s, msg: message)
		}
	}

	/**
	 * processOk(msg: String) -> Void
	 * +OK
	 *
	 */
	fileprivate func processOk(_ msg: String) {
		print("processOk \(msg)")
	}

	/**
	 * processErr(msg: String) -> Void
	 * -ERR
	 *
	 */
	fileprivate func processErr(_ msg: String) {
		print("processErr \(msg)")
	}

	/**
	 * processPing() -> Void
	 * PING keep-alive message
	 * PONG keep-alive response
	 *
	 */
	fileprivate func processPing() {
		sendText(Proto.PONG.rawValue)
	}
}

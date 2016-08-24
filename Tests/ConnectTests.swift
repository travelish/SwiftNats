//
//  ConnectTests.swift
//  SwiftNatsTests
//
//  Created by kakilangit on 1/21/16.
//  Copyright © 2016 Travelish. All rights reserved.
//

import XCTest
@testable import SwiftNats

class ConnectTests: XCTestCase {

	var nats: Nats!
	let validServer = "nats://admin:admin@localhost:4222"
	let wrongServerLocation = "nats://localhost:4221"
	let wrongServerCredential = "nats://root:root@localhost:4212"

	override func setUp() {
		super.setUp()
		nats = Nats(url: wrongServerLocation)
	}

	override func tearDown() {
		super.tearDown()
	}

	// Connection test
	func testConnect() {
		nats.option(validServer)
		nats.connect()
		XCTAssertTrue(nats.isConnected, "Should be connected")
	}

	func testDisconnect() {
		nats.option(validServer)
		nats.connect()
		XCTAssertTrue(nats.isConnected, "Should be connected")

		nats.disconnect()
		XCTAssertFalse(nats.isConnected, "Should be disconnected")
	}

	func testReconnect() {
		nats.option(validServer)
		nats.connect()
		XCTAssertTrue(nats.isConnected, "Should be connected")

		nats.disconnect()
		XCTAssertFalse(nats.isConnected, "Should be disconnected")

		nats.reconnect(wrongServerCredential)
		XCTAssertFalse(nats.isConnected, "Should be not connected")

		nats.reconnect(validServer)
		XCTAssertTrue(nats.isConnected, "Should be reconnected")
	}

	func testConnectWrongServerLocation() {
		nats.option(wrongServerLocation)
		nats.connect()
		XCTAssertFalse(nats.isConnected, "Should be not connected")
	}

	func testConnectWrongServerCredential() {
		nats.option(wrongServerCredential)
		nats.connect()
		XCTAssertFalse(nats.isConnected, "Should be not connected")
	}

	func testPerformanceExample() {
		// This is an example of a performance test case.
		self.measure {
			// Put the code you want to measure the time of here.
		}
	}
}

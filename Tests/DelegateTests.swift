//
//  DelegateTests.swift
//  SwiftNatsTests
//
//  Created by kakilangit on 1/27/16.
//  Copyright © 2016 Travelish. All rights reserved.
//

import XCTest
@testable import SwiftNats

class SpyDelegate: NatsDelegate {
	var msg: NatsMessage? = .none
	var expectation: XCTestExpectation?

	func natsDidConnect(nats: Nats) { }
	func natsDidDisconnect(nats: Nats, error: NSError?) { }
	func natsDidReceiveMessage(nats: Nats, msg: NatsMessage) {
		guard let expectation = expectation else {
			XCTFail("SpyDelegate was not setup correctly. Missing XCTExpectation reference")
			return
		}
		self.msg = msg

		expectation.fulfill()
	}
	func natsDidReceivePing(nats: Nats) { }
}

class DelegateTests: XCTestCase {

	var nats: Nats!
	var testablenats: Nats!
	let spy = SpyDelegate()
	let validServer = "nats://admin:admin@localhost:4222"

	override func setUp() {
		super.setUp()
		testablenats = Nats(url: validServer)
		nats = Nats(url: validServer)
		testablenats.delegate = spy

		_ = [nats, testablenats].map({ $0.connect() })
	}

	override func tearDown() {
		super.tearDown()
	}

	// Subscribe test
	func testPubSub() {
		let subject = "vehicle"
		testablenats.subscribe(subject)

		let expectation = self.expectation(description: "SpyDelegate expectation")
		spy.expectation = expectation

		let delay = 2 * Double(NSEC_PER_SEC)
		let time = DispatchTime.now() + Double(Int64(delay)) / Double(NSEC_PER_SEC)

		// Test Publish
		DispatchQueue.main.asyncAfter(deadline: time) { [weak self] in
			guard let s = self else { return }
			for index in 1...2 {
				s.nats.publish(subject, payload: "\(index)")
			}
		}

		// Test Subscribe
		waitForExpectations(timeout: 10) { error in
			if let error = error {
				XCTFail("waitForExpectationsWithTimeout errored: \(error)")
			}

			guard let result = self.spy.msg else {
				XCTFail("Expected delegate to be called")
				return
			}

			XCTAssertNotNil(result, "Message should be received")
		}
	}

	func testPerformanceExample() {
		// This is an example of a performance test case.
		self.measure {
		}
	}
}

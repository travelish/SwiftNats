# SwiftNats

[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage) ![CocoaPods](https://img.shields.io/cocoapods/v/SwiftNats.svg) ![Platform](https://img.shields.io/badge/platforms-iOS%2012.2-F28D00.svg)

Swift 5.0 client for NATS, the cloud native messaging system. https://nats.io

For Swift 3 version, please check branch Swift3.

## Install
#### CocoaPods

    platform :ios, '12.2'
    use_frameworks!

    pod 'SwiftNats', '~> 5.0.0'

#### Carthage

You can use [Carthage](https://github.com/Carthage/Carthage) to install `SwiftNats` by adding it to your `Cartfile`:

```
github "travelish/SwiftNats" ~> 5.0.0
```

If you use Carthage to build your dependencies, make sure you have added `SwiftNats.framework` to the "Linked Frameworks and Libraries" section of your target, and have included them in your Carthage framework copying build phase.

## Usage

Import the package

    import SwiftNats

Declare it with strong reference

    var pubsub: Nats!

Basic features:

    class ViewController: UIViewController, NatsDelegate {
        var pubsub: Nats!
        override func viewDidLoad() {
            super.viewDidLoad()

            pubsub = Nats(url: "nats://localhost:4222")
            pubsub.delegate = self

            //Connect
            pubsub.connect()

            //Subscribe subject
            let subject = "gossip"
            pubsub.subscribe(subject)

            //Publish
            let time = dispatch_time(DISPATCH_TIME_NOW, Int64(2 * Double(NSEC_PER_SEC)))
            dispatch_after(time, dispatch_get_main_queue()) { [weak self] in
                guard let s = self else { return }
                    for index in 1...2 {
                    s.pubsub.publish(subject, payload: "\(index)")
                }
            }

            //Disconnect
            pubsub.disconnect()
        }

Delegate

    public protocol NatsDelegate: class {
        func natsDidConnect(nats: Nats)
        func natsDidDisconnect(nats: Nats, error: NSError?)
        func natsDidReceiveMessage(nats: Nats, msg: NatsMessage)
        func natsDidReceivePing(nats: Nats)
    }


Why use strong reference a.k.a property? Because of NSStreamDelegate is weak & unsafe, it does not retain the object:

    unowned(unsafe) var delegate: NSStreamDelegate?


## To do

* Synchronous Messaging.
* Request Reply.
* Queueing.
* Testing.


The MIT License (MIT)

Copyright (c) 2016 kakilangit

theguywhodrinkscoffeeandcodes@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

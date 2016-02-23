//
//  RealtimeClient.channel.swift
//  ably
//
//  Created by Ricardo Pereira on 18/01/16.
//  Copyright © 2016 Ably. All rights reserved.
//

import Quick
import Nimble
import Aspects

class RealtimeClientChannel: QuickSpec {
    override func spec() {
        describe("Channel") {

            // RTL1
            it("should process all incoming messages and presence messages as soon as a Channel becomes attached") {
                let options = AblyTests.commonAppSetup()
                let client1 = ARTRealtime(options: options)
                defer { client1.close() }

                let channel1 = client1.channels.get("room")
                channel1.attach()

                waitUntil(timeout: testTimeout) { done in
                    channel1.presence.enterClient("Client 1", data: nil) { errorInfo in
                        expect(errorInfo).to(beNil())
                        done()
                    }
                }

                options.clientId = "Client 2"
                let client2 = ARTRealtime(options: options)
                defer { client2.close() }

                let channel2 = client2.channels.get(channel1.name)
                channel2.attach()

                expect(channel2.presence.syncComplete).to(beFalse())

                expect(channel1.presenceMap.members).to(haveCount(1))
                expect(channel2.presenceMap.members).to(haveCount(0))

                expect(channel2.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                expect(channel2.presence.syncComplete).toEventually(beTrue(), timeout: testTimeout)

                expect(channel1.presenceMap.members).to(haveCount(1))
                expect(channel2.presenceMap.members).to(haveCount(1))

                // Check if receives incoming messages
                channel2.subscribe("Client 1") { message in
                    expect(message.data as? String).to(equal("message"))
                }

                waitUntil(timeout: testTimeout) { done in
                    channel1.publish("message", data: nil) { errorInfo in
                        expect(errorInfo).to(beNil())
                        done()
                    }
                }

                waitUntil(timeout: testTimeout) { done in
                    channel2.presence.enter(nil) { errorInfo in
                        expect(errorInfo).to(beNil())
                        done()
                    }
                }

                expect(channel1.presenceMap.members).to(haveCount(2))
                expect(channel1.presenceMap.members).to(allKeysPass({ $0.hasPrefix("Client") }))
                expect(channel1.presenceMap.members).to(allValuesPass({ $0.action == .Enter }))

                expect(channel2.presenceMap.members).to(haveCount(2))
                expect(channel2.presenceMap.members).to(allKeysPass({ $0.hasPrefix("Client") }))
                expect(channel2.presenceMap.members["Client 1"]!.action).to(equal(ARTPresenceAction.Present))
                expect(channel2.presenceMap.members["Client 2"]!.action).to(equal(ARTPresenceAction.Enter))
            }

            // RTL2
            context("EventEmitter and states") {

                // RTL2a
                it("should implement the EventEmitter and emit events for state changes") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")
                    expect(channel.statesEventEmitter).to(beAKindOf(ARTEventEmitter.self))

                    var channelOnMethodCalled = false
                    channel.testSuite_injectIntoMethod("on:") {
                        channelOnMethodCalled = true
                    }

                    // The `channel.on` should use `statesEventEmitter`
                    var statesEventEmitterOnMethodCalled = false
                    channel.statesEventEmitter.testSuite_injectIntoMethod("on:") {
                        statesEventEmitterOnMethodCalled = true
                    }

                    var emitCounter = 0
                    channel.statesEventEmitter.testSuite_injectIntoMethod("emit:with:") {
                        emitCounter += 1
                    }

                    var states = [ARTRealtimeChannelState]()
                    waitUntil(timeout: testTimeout) { done in
                        channel.on { errorInfo in
                            states += [channel.state]
                            switch channel.state {
                            case .Attached:
                                channel.detach()
                            case .Detached:
                                channel.onError(AblyTests.newErrorProtocolMessage())
                            case .Failed:
                                done()
                            default:
                                break
                            }
                        }
                        channel.attach()
                    }
                    channel.off()

                    expect(channelOnMethodCalled).to(beTrue())
                    expect(statesEventEmitterOnMethodCalled).to(beTrue())
                    expect(emitCounter).to(equal(5))

                    if states.count != 5 {
                        fail("Missing some states")
                        return
                    }

                    expect(states[0].rawValue).to(equal(ARTRealtimeChannelState.Attaching.rawValue), description: "Should be ATTACHING state")
                    expect(states[1].rawValue).to(equal(ARTRealtimeChannelState.Attached.rawValue), description: "Should be ATTACHED state")
                    expect(states[2].rawValue).to(equal(ARTRealtimeChannelState.Detaching.rawValue), description: "Should be DETACHING state")
                    expect(states[3].rawValue).to(equal(ARTRealtimeChannelState.Detached.rawValue), description: "Should be DETACHED state")
                    expect(states[4].rawValue).to(equal(ARTRealtimeChannelState.Failed.rawValue), description: "Should be FAILED state")
                }

            }

            // RTL3
            context("connection state") {

                // RTL3a
                context("changes to FAILED") {

                    it("ATTACHING channel should transition to FAILED") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        channel.attach()
                        let transport = client.transport as! TestProxyTransport
                        transport.actionsIgnored += [.Attached]

                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))

                        waitUntil(timeout: testTimeout) { done in
                            let error = AblyTests.newErrorProtocolMessage()
                            channel.on { errorInfo in
                                if channel.state == .Failed {
                                    guard let errorInfo = errorInfo else {
                                        fail("errorInfo is nil"); done(); return
                                    }
                                    expect(errorInfo).to(equal(error.error))
                                    expect(channel.errorReason).to(equal(errorInfo))
                                    done()
                                }
                            }
                            client.onError(error)
                        }
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Failed))
                    }

                    it("ATTACHED channel should transition to FAILED") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        channel.attach()
                        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                        waitUntil(timeout: testTimeout) { done in
                            let error = AblyTests.newErrorProtocolMessage()
                            channel.on { errorInfo in
                                if channel.state == .Failed {
                                    guard let errorInfo = errorInfo else {
                                        fail("errorInfo is nil"); done(); return
                                    }
                                    expect(errorInfo).to(equal(error.error))
                                    expect(channel.errorReason).to(equal(errorInfo))
                                    done()
                                }
                            }
                            client.onError(error)
                        }
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Failed))
                    }
                    
                }

                // RTL3b
                context("changes to SUSPENDED") {

                    it("ATTACHING channel should transition to DETACHED") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        channel.attach()
                        let transport = client.transport as! TestProxyTransport
                        transport.actionsIgnored += [.Attached]

                        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.Connected), timeout: testTimeout)
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                        client.onSuspended()
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Detached))
                    }

                    it("ATTACHED channel should transition to DETACHED") {
                        let options = AblyTests.commonAppSetup()
                        let client = ARTRealtime(options: options)
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        channel.attach()
                        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)
                        client.onSuspended()
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Detached))
                    }

                }

                // RTL3b
                context("changes to CLOSED") {

                    it("ATTACHING channel should transition to DETACHED") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        channel.attach()
                        let transport = client.transport as! TestProxyTransport
                        transport.actionsIgnored += [.Attached]

                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                        client.close()
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Closing))
                        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Detached), timeout: testTimeout)
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Closed))
                    }

                    it("ATTACHED channel should transition to DETACHED") {
                        let options = AblyTests.commonAppSetup()
                        let client = ARTRealtime(options: options)
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        channel.attach()

                        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)
                        client.close()
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Closing))
                        expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Detached), timeout: testTimeout)
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Closed))
                    }

                }

            }

            // RTL4
            describe("attach") {

                // RTL4a
                it("if already ATTACHED or ATTACHING nothing is done") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    var errorInfo: ARTErrorInfo?
                    let channel = client.channels.get("test")

                    channel.attach { errorInfo in
                        expect(errorInfo).to(beNil())
                    }
                    expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))

                    channel.attach { errorInfo in
                        expect(errorInfo).to(beNil())
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                    }

                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach { errorInfo in
                            expect(errorInfo).to(beNil())
                            expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                            done()
                        }
                    }
                }

                // RTL4b
                context("results in an error if the connection state is") {

                    it("CLOSING") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }

                        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.Connected), timeout: testTimeout)
                        let transport = client.transport as! TestProxyTransport
                        transport.actionsIgnored += [.Closed]

                        let channel = client.channels.get("test")

                        client.close()
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Closing))

                        expect(channel.attach()).toNot(beNil())
                    }

                    it("CLOSED") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }

                        let channel = client.channels.get("test")

                        client.close()
                        expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.Closed), timeout: testTimeout)

                        expect(channel.attach()).toNot(beNil())
                    }

                    it("SUSPENDED") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        client.onSuspended()
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Suspended))
                        expect(channel.attach()).toNot(beNil())
                    }

                    it("FAILED") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }

                        let channel = client.channels.get("test")
                        client.onError(AblyTests.newErrorProtocolMessage())
                        expect(client.connection.state).to(equal(ARTRealtimeConnectionState.Failed))
                        expect(channel.attach()).toNot(beNil())
                    }

                }

                // RTL4c
                it("should send an ATTACH ProtocolMessage, change state to ATTACHING and change state to ATTACHED after confirmation") {
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    client.setTransportClass(TestProxyTransport.self)
                    client.connect()
                    defer { client.close() }

                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.Connected), timeout: testTimeout)
                    let transport = client.transport as! TestProxyTransport

                    let channel = client.channels.get("test")
                    channel.attach()

                    expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                    expect(transport.protocolMessagesSent.filter({ $0.action == .Attach })).to(haveCount(1))

                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)
                    expect(transport.protocolMessagesReceived.filter({ $0.action == .Attached })).to(haveCount(1))
                }

                // RTL4e
                it("should transition the channel state to FAILED if the user does not have sufficient permissions") {
                    let options = AblyTests.clientOptions()
                    options.token = getTestToken(capability: "{ \"main\":[\"subscribe\"] }")
                    let client = ARTRealtime(options: options)
                    defer { client.close() }

                    let channel = client.channels.get("test")
                    channel.attach()

                    channel.on { errorInfo in
                        if channel.state == .Failed {
                            expect(errorInfo!.code).to(equal(40160))
                        }
                    }

                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Failed), timeout: testTimeout)
                }

                // RTL4f
                it("should transition the channel state to FAILED if ATTACHED ProtocolMessage is not received") {
                    ARTDefault.setRealtimeRequestTimeout(3.0)
                    let options = AblyTests.commonAppSetup()
                    options.autoConnect = false
                    let client = ARTRealtime(options: options)
                    client.setTransportClass(TestProxyTransport.self)
                    client.connect()
                    defer { client.close() }

                    expect(client.connection.state).toEventually(equal(ARTRealtimeConnectionState.Connected), timeout: testTimeout)
                    let transport = client.transport as! TestProxyTransport
                    transport.actionsIgnored += [.Attached]

                    var callbackCalled = false
                    let channel = client.channels.get("test")
                    channel.attach { errorInfo in
                        expect(errorInfo).toNot(beNil())
                        expect(errorInfo).to(equal(channel.errorReason))
                        callbackCalled = true
                    }
                    let start = NSDate()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Failed), timeout: testTimeout)
                    expect(channel.errorReason).toNot(beNil())
                    expect(callbackCalled).to(beTrue())
                    let end = NSDate()
                    expect(start.dateByAddingTimeInterval(3.0)).to(beCloseTo(end, within: 0.5))
                }

                it("if called with a callback should call it once attached") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach { errorInfo in
                            expect(errorInfo).to(beNil())
                            expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                            done()
                        }
                    }
                }

                it("if called with a callback and already attaching should call the callback once attached") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach()
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                        channel.attach { errorInfo in
                            expect(errorInfo).to(beNil())
                            expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                            done()
                        }
                    }
                }

                it("if called with a callback and already attached should call the callback with nil error") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    channel.attach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.attach { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }
                }
            }

            describe("detach") {
                it("if called with a callback should call it once detached") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    channel.attach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.detach { errorInfo in
                            expect(errorInfo).to(beNil())
                            expect(channel.state).to(equal(ARTRealtimeChannelState.Detached))
                            done()
                        }
                    }
                }

                it("if called with a callback and already detaching should call the callback once detached") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    channel.attach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.detach()
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Detaching))
                        channel.detach { errorInfo in
                            expect(errorInfo).to(beNil())
                            expect(channel.state).to(equal(ARTRealtimeChannelState.Detached))
                            done()
                        }
                    }
                }

                it("if called with a callback and already detached should should call the callback with nil error") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    channel.attach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)
                    channel.detach()
                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Detached), timeout: testTimeout)

                    waitUntil(timeout: testTimeout) { done in
                        channel.detach { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }
                }
            }

            // RTL6
            describe("publish") {

                // RTL6a
                it("should encode messages in the same way as the RestChannel") {
                    let data = ["value":1]

                    let rest = ARTRest(options: AblyTests.commonAppSetup())
                    let restChannel = rest.channels.get("test")

                    var restEncodedMessage: ARTMessage?
                    restChannel.testSuite_getReturnValueFrom(Selector("encodeMessageIfNeeded:")) { value in
                        restEncodedMessage = value as? ARTMessage
                    }

                    waitUntil(timeout: testTimeout) { done in
                        restChannel.publish(nil, data: data) { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }

                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.close() }
                    let realtimeChannel = realtime.channels.get("test")
                    realtimeChannel.attach()
                    expect(realtimeChannel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    var realtimeEncodedMessage: ARTMessage?
                    realtimeChannel.testSuite_getReturnValueFrom(Selector("encodeMessageIfNeeded:")) { value in
                        realtimeEncodedMessage = value as? ARTMessage
                    }

                    waitUntil(timeout: testTimeout) { done in
                        realtimeChannel.publish(nil, data: data) { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }

                    expect(restEncodedMessage!.data as? NSObject).to(equal(realtimeEncodedMessage!.data as? NSObject))
                    expect(restEncodedMessage!.data).toNot(beNil())
                    expect(realtimeEncodedMessage!.data).toNot(beNil())
                    expect(restEncodedMessage!.encoding).to(equal(realtimeEncodedMessage!.encoding))
                    expect(restEncodedMessage!.encoding).toNot(beNil())
                    expect(realtimeEncodedMessage!.encoding).toNot(beNil())
                }

                // RTL6b
                context("should invoke callback") {

                    it("when the message is successfully delivered") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.connection.on { stateChange in
                                let stateChange = stateChange!
                                let state = stateChange.current
                                let error = stateChange.reason
                                if state == .Connected {
                                    let channel = client.channels.get("test")
                                    channel.on { errorInfo in
                                        if channel.state == .Attached {
                                            channel.publish(nil, data: "message") { errorInfo in
                                                expect(errorInfo).to(beNil())
                                                done()
                                            }
                                        }
                                    }
                                    channel.attach()
                                }
                            }
                        }
                    }

                    it("upon failure") {
                        let options = AblyTests.clientOptions()
                        options.token = getTestToken(capability: "{ \"test\":[\"subscribe\"] }")
                        let client = ARTRealtime(options: options)
                        defer { client.close() }

                        waitUntil(timeout: testTimeout) { done in
                            client.connection.on { stateChange in
                                let stateChange = stateChange!
                                let state = stateChange.current
                                let error = stateChange.reason
                                if state == .Connected {
                                    let channel = client.channels.get("test")
                                    channel.on { errorInfo in
                                        if channel.state == .Attached {
                                            channel.publish(nil, data: "message") { errorInfo in
                                                expect(errorInfo).toNot(beNil())
                                                guard let errorInfo = errorInfo else {
                                                    XCTFail("ErrorInfo is nil"); done(); return
                                                }
                                                // Unable to perform channel operation
                                                expect(errorInfo.code).to(equal(40160))
                                                done()
                                            }
                                        }
                                    }
                                    channel.attach()
                                }
                            }
                        }
                    }

                    class TotalMessages {
                        static let expected = 50
                        static var succeeded = 0
                        static var failed = 0
                        private init() {}
                    }

                    it("for all messages published") {
                        let options = AblyTests.clientOptions()
                        options.token = getTestToken(capability: "{ \"channelToSucceed\":[\"subscribe\", \"publish\"], \"channelToFail\":[\"subscribe\"] }")
                        let client = ARTRealtime(options: options)
                        defer { client.close() }

                        TotalMessages.succeeded = 0
                        TotalMessages.failed = 0

                        let channelToSucceed = client.channels.get("channelToSucceed")
                        channelToSucceed.on { errorInfo in
                            if channelToSucceed.state == .Attached {
                                for index in 1...TotalMessages.expected {
                                    channelToSucceed.publish(nil, data: "message\(index)") { errorInfo in
                                        if errorInfo == nil {
                                            expect(index).to(equal(++TotalMessages.succeeded), description: "Callback was invoked with an invalid sequence")
                                        }
                                    }
                                }
                            }
                        }
                        channelToSucceed.attach()

                        let channelToFail = client.channels.get("channelToFail")
                        channelToFail.on { errorInfo in
                            if channelToFail.state == .Attached {
                                for index in 1...TotalMessages.expected {
                                    channelToFail.publish(nil, data: "message\(index)") { errorInfo in
                                        if errorInfo != nil {
                                            expect(index).to(equal(++TotalMessages.failed), description: "Callback was invoked with an invalid sequence")
                                        }
                                    }
                                }
                            }
                        }
                        channelToFail.attach()

                        expect(TotalMessages.succeeded).toEventually(equal(TotalMessages.expected), timeout: testTimeout)
                        expect(TotalMessages.failed).toEventually(equal(TotalMessages.expected), timeout: testTimeout)
                    }

                }

                // RTL6e
                context("Unidentified clients using Basic Auth") {

                    // RTL6e1
                    it("should have the provided clientId on received message when it was published with clientId") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }

                        expect(client.auth.clientId).to(beNil())

                        let channel = client.channels.get("test")

                        var resultClientId: String?
                        channel.subscribe() { message in
                            resultClientId = message.clientId
                        }

                        let message = ARTMessage(name: nil, data: "message")
                        message.clientId = "client_string"

                        channel.publish([message]) { errorInfo in
                            expect(errorInfo).to(beNil())
                        }

                        expect(resultClientId).toEventually(equal(message.clientId), timeout: testTimeout)
                    }

                }

                // RTL6i
                context("expect either") {

                    it("an array of Message objects") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }
                        let channel = client.channels.get("test")
                        typealias JSONObject = NSDictionary

                        var result = [JSONObject]()
                        channel.subscribe { message in
                            result.append(message.data as! JSONObject)
                        }

                        let messages = [ARTMessage(name: nil, data: ["key":1]), ARTMessage(name: nil, data: ["key":2])]
                        channel.publish(messages)

                        let transport = client.transport as! TestProxyTransport

                        expect(transport.protocolMessagesSent.filter{ $0.action == .Message }).toEventually(haveCount(1), timeout: testTimeout)
                        expect(result).toEventually(equal(messages.map{ $0.data as! JSONObject }), timeout: testTimeout)
                    }

                    it("a name string and data payload") {
                        let client = ARTRealtime(options: AblyTests.commonAppSetup())
                        defer { client.close() }
                        let channel = client.channels.get("test")

                        let expectedResult = "string_data"
                        var result: String?

                        channel.subscribe("event") { message in
                            result = message.data as? String
                        }

                        channel.publish("event", data: expectedResult, cb: nil)

                        expect(result).toEventually(equal(expectedResult), timeout: testTimeout)
                    }

                    it("allows name to be null") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }
                        let channel = client.channels.get("test")

                        let expectedObject = ["data": "message"]

                        var resultMessage: ARTMessage?
                        channel.subscribe { message in
                            resultMessage = message
                        }

                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(nil, data: expectedObject["data"]) { errorInfo in
                                expect(errorInfo).to(beNil())
                                done()
                            }
                        }

                        let transport = client.transport as! TestProxyTransport

                        let rawMessagesSent = transport.rawDataSent.toJSONArray.filter({ $0["action"] == ARTProtocolMessageAction.Message.rawValue })
                        let messagesList = (rawMessagesSent[0] as! NSDictionary)["messages"] as! NSArray
                        let resultObject = messagesList[0] as! NSDictionary

                        expect(resultObject).to(equal(expectedObject))

                        expect(resultMessage).toNotEventually(beNil(), timeout: testTimeout)
                        expect(resultMessage!.name).to(beNil())
                        expect(resultMessage!.data as? String).to(equal(expectedObject["data"]))
                    }

                    it("allows data to be null") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }
                        let channel = client.channels.get("test")

                        let expectedObject = ["name": "click"]

                        var resultMessage: ARTMessage?
                        channel.subscribe(expectedObject["name"]!) { message in
                            resultMessage = message
                        }

                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(expectedObject["name"], data: nil) { errorInfo in
                                expect(errorInfo).to(beNil())
                                done()
                            }
                        }

                        let transport = client.transport as! TestProxyTransport

                        let rawMessagesSent = transport.rawDataSent.toJSONArray.filter({ $0["action"] == ARTProtocolMessageAction.Message.rawValue })
                        let messagesList = (rawMessagesSent[0] as! NSDictionary)["messages"] as! NSArray
                        let resultObject = messagesList[0] as! NSDictionary

                        expect(resultObject).to(equal(expectedObject))

                        expect(resultMessage).toNotEventually(beNil(), timeout: testTimeout)
                        expect(resultMessage!.name).to(equal(expectedObject["name"]))
                        expect(resultMessage!.data).to(beNil())
                    }

                    it("allows name and data to be assigned") {
                        let options = AblyTests.commonAppSetup()
                        options.autoConnect = false
                        let client = ARTRealtime(options: options)
                        client.setTransportClass(TestProxyTransport.self)
                        client.connect()
                        defer { client.close() }
                        let channel = client.channels.get("test")

                        let expectedObject = ["name":"click", "data":"message"]

                        waitUntil(timeout: testTimeout) { done in
                            channel.publish(expectedObject["name"], data: expectedObject["data"]) { errorInfo in
                                expect(errorInfo).to(beNil())
                                done()
                            }
                        }

                        let transport = client.transport as! TestProxyTransport

                        let rawMessagesSent = transport.rawDataSent.toJSONArray.filter({ $0["action"] == ARTProtocolMessageAction.Message.rawValue })
                        let messagesList = (rawMessagesSent[0] as! NSDictionary)["messages"] as! NSArray
                        let resultObject = messagesList[0] as! NSDictionary

                        expect(resultObject).to(equal(expectedObject))
                    }

                }

                // RTL6g
                context("Identified clients with clientId") {

                    // RTL6g1
                    context("When publishing a Message with clientId set to null") {

                        // RTL6g1a & RTL6g1b
                        pending("should be unnecessary to set clientId of the Message before publishing and have clientId value as null for the Message when received") {
                            let options = AblyTests.commonAppSetup()
                            options.clientId = "client_string"
                            options.autoConnect = false
                            let client = ARTRealtime(options: options)
                            client.setTransportClass(TestProxyTransport.self)
                            client.connect()
                            defer { client.close() }
                            let channel = client.channels.get("test")

                            let message = ARTMessage(name: nil, data: "message")
                            expect(message.clientId).to(beNil())

                            waitUntil(timeout: testTimeout) { done in
                                channel.subscribe() { message in
                                    expect(message.clientId).to(beNil())
                                    done()
                                }
                                channel.publish([message])
                            }

                            let transport = client.transport as! TestProxyTransport

                            let messageSent = transport.protocolMessagesSent.filter({ $0.action == .Message })[0]
                            expect(messageSent.messages![0].clientId).to(beNil())

                            let messageReceived = transport.protocolMessagesReceived.filter({ $0.action == .Message })[0]
                            expect(messageReceived.messages![0].clientId).to(beNil())
                        }

                    }

                }

            }

            // RTL7
            context("subscribe") {

                // RTL7a
                it("with no arguments subscribes a listener to all messages") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    class Test {
                        static var counter = 0
                        private init() {}
                    }

                    channel.subscribe { message in
                        expect(message.data as? String).to(equal("message"))
                        Test.counter += 1
                    }

                    channel.publish(nil, data: "message")
                    channel.publish("eventA", data: "message")
                    channel.publish("eventB", data: "message")

                    expect(Test.counter).toEventually(equal(3), timeout: testTimeout)
                }

                // RTL7b
                it("with a single name argument subscribes a listener to only messages whose name member matches the string name") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    class Test {
                        static var counter = 0
                        private init() {}
                    }

                    channel.subscribe("eventA") { message in
                        expect(message.name).to(equal("eventA"))
                        expect(message.data as? String).to(equal("message"))
                        Test.counter += 1
                    }

                    channel.publish(nil, data: "message")
                    channel.publish("eventA", data: "message")
                    channel.publish("eventB", data: "message")
                    channel.publish("eventA", data: "message")

                    expect(Test.counter).toEventually(equal(2), timeout: testTimeout)
                }

                it("with a attach callback should subscribe and call the callback when attached") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    let publishedMessage = ARTMessage(name: "foo", data: "bar")

                    waitUntil(timeout: testTimeout) { done in
                        expect(channel.state).to(equal(ARTRealtimeChannelState.Initialised))

                        channel.subscribeWithAttachCallback({ errorInfo in
                            expect(errorInfo).to(beNil())
                            expect(channel.state).to(equal(ARTRealtimeChannelState.Attached))
                            channel.publish([publishedMessage])
                        }) { message in
                            expect(message.name).to(equal(publishedMessage.name))
                            expect(message.data as? NSObject).to(equal(publishedMessage.data as? NSObject))
                            done()
                        }

                        expect(channel.state).to(equal(ARTRealtimeChannelState.Attaching))
                    }
                }

                // RTL7c
                it("should implicitly attach the channel") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    channel.subscribe { _ in }

                    expect(channel.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)
                }

                // RTL7c
                pending("should result in an error if channel is in the FAILED state") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")
                    channel.onError(AblyTests.newErrorProtocolMessage())
                    expect(channel.state).to(equal(ARTRealtimeChannelState.Failed))

                    waitUntil(timeout: testTimeout) { done in
                        channel.subscribe { message in
                            // FIXME: error handling
                            //https://github.com/ably/ably-ios/pull/208#discussion_r53043622
                            done()
                        }
                    }
                }

                // RTL7d
                pending("should deliver the message even if there is an error while decoding") {

                    for cryptoTest in [CryptoTest.aes128, CryptoTest.aes256] {
                        it("using \(cryptoTest) ") {
                            let options = AblyTests.commonAppSetup()
                            options.autoConnect = false
                            let client = ARTRealtime(options: options)
                            client.setTransportClass(TestProxyTransport.self)
                            client.connect()
                            defer { client.close() }

                            let (keyData, ivData, messages) = AblyTests.loadCryptoTestData(cryptoTest)
                            let testMessage = messages[0]

                            let cipherParams = ARTCrypto.defaultParamsWithKey(keyData, iv: ivData)
                            let channelOptions = ARTChannelOptions(encrypted: cipherParams)
                            let channel = client.channels.get("test", options: channelOptions)

                            let transport = client.transport as! TestProxyTransport

                            transport.beforeProcessingSentMessage = { protocolMessage in
                                if protocolMessage.action == .Message {
                                    expect(protocolMessage.messages![0].data as? String).to(equal(testMessage.encrypted.data))
                                    expect(protocolMessage.messages![0].encoding).to(equal(testMessage.encrypted.encoding))
                                }
                            }

                            transport.beforeProcessingReceivedMessage = { protocolMessage in
                                if protocolMessage.action == .Message {
                                    expect(protocolMessage.messages![0].data as? String).to(equal(testMessage.encrypted.data))
                                    expect(protocolMessage.messages![0].encoding).to(equal(testMessage.encrypted.encoding))
                                    // Force an error decoding a message
                                    protocolMessage.messages![0].encoding = "bad_encoding_type"
                                }
                            }

                            waitUntil(timeout: testTimeout) { done in
                                let logTime = NSDate()

                                channel.subscribe(testMessage.encoded.name) { message in
                                    expect(message.data as? String).to(equal(testMessage.encrypted.data))

                                    let logs = querySyslog(forLogsAfter: logTime)
                                    let line = logs.reduce("") { $0 + "; " + $1 } //Reduce in one line
                                    expect(line).to(contain("ERROR: Failed to decode data as 'bad_encoding_type' encoding is unknown"))

                                    expect(channel.errorReason!.message).to(contain("Failed to decode data as 'bad_encoding_type' encoding is unknown"))

                                    done()
                                }

                                channel.publish(testMessage.encoded.name, data: testMessage.encoded.data)
                            }
                        }
                    }

                }

                // RTL7f
                it("should exist ensuring published messages are not echoed back to the subscriber when echoMessages is false") {
                    let options = AblyTests.commonAppSetup()
                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }

                    options.echoMessages = false
                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }

                    let channel1 = client1.channels.get("test")
                    let channel2 = client2.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel1.subscribe { message in
                            expect(message.data as? String).to(equal("message"))
                            delay(5.0) { done() }
                        }

                        channel2.subscribe { message in
                            fail("Shouldn't receive the message")
                        }

                        channel2.publish(nil, data: "message")
                    }
                }

            }

            // RTL8
            context("unsubscribe") {

                // RTL8a
                it("with no arguments unsubscribes the provided listener to all messages if subscribed") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let listener = channel.subscribe { message in
                            fail("Listener shouldn't exist")
                            done()
                        }

                        channel.unsubscribe(listener)

                        channel.publish(nil, data: "message") { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }
                }

                // RTL8b
                it("with a single name argument unsubscribes the provided listener if previously subscribed with a name-specific subscription") {
                    let client = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { client.close() }

                    let channel = client.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        let eventAListener = channel.subscribe("eventA") { message in
                            fail("Listener shouldn't exist")
                            done()
                        }

                        channel.unsubscribe("eventA", listener: eventAListener)

                        channel.publish("eventA", data: "message") { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }
                }

            }

            // RTL10
            context("history") {

                // RTL10a 
                it("should support all the same params as Rest") {
                    let options = AblyTests.commonAppSetup()

                    let rest = ARTRest(options: options)

                    let realtime = ARTRealtime(options: options)
                    defer { realtime.close() }

                    var restChannelHistoryMethodWasCalled = false
                    ARTRestChannel.testSuite_injectIntoClassMethod("history:callback:error:") {
                        restChannelHistoryMethodWasCalled = true
                    }

                    let channelRest = rest.channels.get("test")
                    let channelRealtime = realtime.channels.get("test")

                    let queryRealtime = ARTRealtimeHistoryQuery()
                    queryRealtime.start = NSDate()
                    queryRealtime.end = NSDate()
                    queryRealtime.direction = .Forwards
                    queryRealtime.limit = 50

                    let queryRest = queryRealtime as ARTDataQuery

                    waitUntil(timeout: testTimeout) { done in
                        try! channelRest.history(queryRest) { _, _ in
                            done()
                        }
                    }
                    expect(restChannelHistoryMethodWasCalled).to(beTrue())
                    restChannelHistoryMethodWasCalled = false

                    waitUntil(timeout: testTimeout) { done in
                        try! channelRealtime.history(queryRealtime) { _, _ in
                            done()
                        }
                    }
                    expect(restChannelHistoryMethodWasCalled).to(beTrue())
                }

                // RTL10c
                it("should return a PaginatedResult page") {
                    let realtime = ARTRealtime(options: AblyTests.commonAppSetup())
                    defer { realtime.close() }
                    let channel = realtime.channels.get("test")

                    waitUntil(timeout: testTimeout) { done in
                        channel.publish(nil, data: "message") { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        try! channel.history { result, _ in
                            expect(result).to(beAKindOf(ARTPaginatedResult))
                            expect(result!.items).to(haveCount(1))
                            expect(result!.hasNext).to(beFalse())
                            // Obj-C generics get lost in translation
                            //Something related: https://lists.swift.org/pipermail/swift-evolution/Week-of-Mon-20160111/006792.html
                            let messages = result!.items as! [ARTMessage]
                            expect(messages[0].data as? String).to(equal("message"))
                            done()
                        }
                    }
                }

                // RTL10d
                it("should retrieve all available messages") {
                    let options = AblyTests.commonAppSetup()
                    let client1 = ARTRealtime(options: options)
                    defer { client1.close() }

                    let client2 = ARTRealtime(options: options)
                    defer { client2.close() }

                    let channel1 = client1.channels.get("test")
                    channel1.attach()
                    expect(channel1.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    var messages = [ARTMessage]()
                    for i in 0..<20 {
                        messages.append(ARTMessage(name: nil, data: "message \(i)"))
                    }
                    waitUntil(timeout: testTimeout) { done in
                        channel1.publish(messages) { errorInfo in
                            expect(errorInfo).to(beNil())
                            done()
                        }
                    }

                    let channel2 = client2.channels.get("test")
                    channel2.attach()
                    expect(channel2.state).toEventually(equal(ARTRealtimeChannelState.Attached), timeout: testTimeout)

                    let query = ARTRealtimeHistoryQuery()
                    query.limit = 10

                    waitUntil(timeout: testTimeout) { done in
                        try! channel2.history(query) { result, errorInfo in
                            expect(result!.items).to(haveCount(10))
                            expect(result!.hasNext).to(beTrue())
                            expect(result!.isLast).to(beFalse())
                            expect((result!.items.first! as! ARTMessage).data as? String).to(equal("message 19"))
                            expect((result!.items.last! as! ARTMessage).data as? String).to(equal("message 10"))

                            result!.next { result, errorInfo in
                                expect(result!.items).to(haveCount(10))
                                expect(result!.hasNext).to(beFalse())
                                expect(result!.isLast).to(beTrue())
                                expect((result!.items.first! as! ARTMessage).data as? String).to(equal("message 9"))
                                expect((result!.items.last! as! ARTMessage).data as? String).to(equal("message 0"))
                                done()
                            }
                        }
                    }
                }

            }

        }
    }
}

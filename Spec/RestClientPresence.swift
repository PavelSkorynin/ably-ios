//
//  RestClientPresence.swift
//  Ably
//
//  Created by Ricardo Pereira on 18/03/16.
//  Copyright © 2016 Ably. All rights reserved.
//

import Quick
import Nimble

class RestClientPresence: QuickSpec {
    override func spec() {
        describe("Presence") {

            // RSP3
            context("get") {

                // RSP3a
                it("should return a PaginatedResult page containing the first page of members") {
                    let options = AblyTests.commonAppSetup()
                    let client = ARTRest(options: options)
                    let channel = client.channels.get("test")

                    var disposable = [ARTRealtime]()
                    defer {
                        for clientItem in disposable {
                            clientItem.close()
                        }
                    }

                    let expectedData = "online"
                    let expectedPattern = "^user(\\d+)$"
                    waitUntil(timeout: testTimeout) { done in
                        // Load 150 members (2 pages)
                        disposable += AblyTests.addMembersSequentiallyToChannel("test", members: 150, data:expectedData, options: options) {
                            done()
                        }
                    }

                    waitUntil(timeout: testTimeout) { done in
                        channel.presence.get { membersPage, error in
                            expect(error).to(beNil())

                            let membersPage = membersPage!
                            expect(membersPage).to(beAnInstanceOf(ARTPaginatedResult))
                            expect(membersPage.items).to(haveCount(100))

                            let members = membersPage.items as! [ARTPresenceMessage]
                            expect(members).to(allPass({ member in
                                return NSRegularExpression.match(member!.clientId, pattern: expectedPattern)
                                    && (member!.data as? NSObject) == expectedData
                            }))

                            expect(membersPage.hasNext).to(beTrue())
                            expect(membersPage.isLast).to(beFalse())

                            membersPage.next { nextPage, error in
                                expect(error).to(beNil())
                                let nextPage = nextPage!
                                expect(nextPage).to(beAnInstanceOf(ARTPaginatedResult))
                                expect(nextPage.items).to(haveCount(50))

                                let members = nextPage.items as! [ARTPresenceMessage]
                                expect(members).to(allPass({ member in
                                    return NSRegularExpression.match(member!.clientId, pattern: expectedPattern)
                                        && (member!.data as? NSObject) == expectedData
                                }))

                                expect(nextPage.hasNext).to(beFalse())
                                expect(nextPage.isLast).to(beTrue())
                                done()
                            }
                        }
                    }
                }

                // RSP3a1
                it("limit should support up to 1000 items") {
                    let client = ARTRest(options: AblyTests.commonAppSetup())
                    let channel = client.channels.get("test")

                    let query = ARTPresenceQuery()
                    expect(query.limit).to(equal(100))

                    query.limit = 1001
                    expect{ try channel.presence.get(query, callback: { _, _ in }) }.to(throwError())

                    query.limit = 1000
                    expect{ try channel.presence.get(query, callback: { _, _ in }) }.toNot(throwError())
                }

            }

        }
    }
}


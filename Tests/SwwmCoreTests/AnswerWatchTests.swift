//
//  AnswerWatchTests.swift
//  SwwmCoreTests
//
//  Created by Yesset Murat on 04.11.2026.
//

import Testing
@testable import SwwmCore

@Test func answerAfterNoAnswerReportsTheWindowsOnce() {
    var w = AnswerWatch()
    w.noAnswer(4)
    w.noAnswer(5)

    #expect(w.answered() == [4, 5])
    #expect(w.answered() == [])
}

@Test func answersWithoutAMissReportNothing() {
    var w = AnswerWatch()
    #expect(w.answered() == [])
}

import XCTest

@MainActor
final class PromptiUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testHomeVisualState() {
        launch(arguments: ["-prompti-demo"])

        XCTAssertTrue(app.buttons["home.destination"].waitForExistence(timeout: 5))
        attachScreenshot(named: "home")
    }

    func testDestinationPickerVisualState() {
        launch(arguments: ["-prompti-demo"])

        let destination = app.buttons["home.destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()

        XCTAssertTrue(app.buttons["destination.close"].waitForExistence(timeout: 5))
        attachScreenshot(named: "destination-picker")
    }

    func testDestinationFiltersAndScrollBoundaries() {
        launch(arguments: ["-prompti-demo"])
        app.buttons["home.destination"].tap()
        let list = app.scrollViews["destination.list"]
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        attachScreenshot(named: "destinations-top")
        list.swipeUp()
        attachScreenshot(named: "destinations-middle")

        let filters = app.scrollViews["destination.filters"]
        let russian = app.buttons["destination.filter.ru"]
        // XCTest can fail an isHittable query for a fully offscreen element.
        // Bring the complete chip into the viewport before asking for a hit point.
        for _ in 0..<4 {
            if filters.frame.contains(russian.frame) { break }
            filters.swipeLeft()
        }
        XCTAssertTrue(russian.isHittable)
        XCTAssertTrue(["Russian", "俄语"].contains(russian.label))
        let unselectedWidth = russian.frame.width
        attachScreenshot(named: "language-filter-unselected")
        russian.tap()
        XCTAssertTrue(app.buttons["destination.moscow"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["destination.moscow"].isHittable)
        XCTAssertGreaterThan(russian.frame.width, unselectedWidth + 10)
        attachScreenshot(named: "language-filter-selected")

        list.swipeUp(velocity: .fast)
        XCTAssertTrue(app.buttons["destination.dubai"].isHittable)
        attachScreenshot(named: "destinations-bottom")

        let search = app.searchFields.firstMatch
        search.tap()
        // Allow the live search layout to settle between key events.
        for character in "Moscow" { search.typeText(String(character)) }
        search.typeText("\n")
        XCTAssertEqual(search.value as? String, "Moscow")
        XCTAssertTrue(app.buttons["destination.moscow"].waitForExistence(timeout: 5))
        attachScreenshot(named: "destinations-short")
    }

    func testSettingsVisualState() {
        launch(arguments: ["-prompti-demo"])

        let settings = app.buttons["home.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        XCTAssertTrue(app.buttons["settings.done"].waitForExistence(timeout: 5))
        attachScreenshot(named: "settings")
    }

    func testJevReviewSettingsEnglishLight() { verifyJevReviewSettings(language: "en", appearance: "light") }
    func testJevReviewSettingsChineseDark() { verifyJevReviewSettings(language: "zh-Hans", appearance: "dark") }

    private func verifyJevReviewSettings(language: String, appearance: String) {
        launch(arguments: ["-prompti-demo", "-prompti-ui-jev-probe", "-prompti-ui-\(appearance)",
                           "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"])
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
        app.buttons["home.settings"].tap()
        let picker = app.buttons["review.provider"]
        for _ in 0..<5 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(picker.isHittable)
        XCTAssertFalse(app.secureTextFields["review.apiKey"].exists)
        picker.tap()
        app.buttons["TypeSafe Jev"].tap()
        let key = app.secureTextFields["review.apiKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 3))
        let done = app.buttons["settings.done"]
        let test = app.buttons["review.test"]
        XCTAssertFalse(done.isEnabled)
        XCTAssertFalse(test.isEnabled)
        key.tap()
        key.typeText("fixture-jev-ui")
        for _ in 0..<3 {
            if test.isHittable { break }
            app.swipeUp()
        }
        test.tap()
        let verified = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: done)
        XCTAssertEqual(XCTWaiter.wait(for: [verified], timeout: 5), .completed)
        XCTAssertTrue(app.descendants(matching: .any)["review.status"].exists)
        for _ in 0..<5 {
            if picker.exists && picker.isHittable { break }
            app.swipeDown()
        }
        XCTAssertTrue(picker.isHittable)
        for _ in 0..<4 {
            let offset = min(180, max(-180, 330 - key.frame.minY))
            if abs(offset) < 20 { break }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: offset)),
                        withVelocity: .slow, thenHoldForDuration: 0.5)
        }
        XCTAssertTrue(test.isHittable)
        attachScreenshot(named: "jev-review-\(language)-\(appearance)")
        let details = app.buttons["review.details"]
        XCTAssertTrue(details.isHittable)
        details.tap()
        let reviewDetail = language == "en"
            ? "Jev works best in English. Review quality in other languages needs validation."
            : "Jev 的英语表现最好，其他语言的审核质量仍需验证。"
        XCTAssertTrue(app.staticTexts[reviewDetail].waitForExistence(timeout: 2))
        attachScreenshot(named: "jev-details-\(language)-\(appearance)")
        details.tap()
        for _ in 0..<3 {
            if key.isHittable { break }
            app.swipeDown()
        }
        key.tap()
        key.typeText("-changed")
        XCTAssertFalse(done.isEnabled)
        app.buttons["settings.cancel"].tap()
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 3))
        app.buttons["home.settings"].tap()
        XCTAssertTrue(done.waitForExistence(timeout: 3))
        for _ in 0..<5 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        XCTAssertFalse(app.secureTextFields["review.apiKey"].exists)
        XCTAssertTrue(done.isEnabled)
        if language == "en" {
            picker.tap()
            app.buttons["TypeSafe Jev"].tap()
            XCTAssertFalse(test.isEnabled)
            key.tap()
            key.typeText("fixture-jev-save")
            test.tap()
            let savedConnection = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: done)
            XCTAssertEqual(XCTWaiter.wait(for: [savedConnection], timeout: 5), .completed)
            done.tap()
            XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 3))
            app.buttons["home.settings"].tap()
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            XCTAssertTrue(done.isEnabled)
            let remove = app.buttons["review.removeKey"]
            for _ in 0..<5 {
                if remove.exists && remove.isHittable { break }
                app.swipeUp()
            }
            remove.tap()
            app.buttons["settings.cancel"].tap()
            XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 3))
            app.buttons["home.settings"].tap()
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            for _ in 0..<5 {
                if remove.exists && remove.isHittable { break }
                app.swipeUp()
            }
            // Cancelling the removal leaves the existing key and enabled mode intact.
            XCTAssertTrue(done.isEnabled)
            remove.tap()
            done.tap()
            XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 3))
            app.buttons["home.settings"].tap()
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            for _ in 0..<5 {
                if picker.exists && picker.isHittable { break }
                app.swipeUp()
            }
            picker.tap()
            app.buttons["TypeSafe Jev"].tap()
            XCTAssertFalse(done.isEnabled)
            XCTAssertFalse(test.isEnabled)
            XCTAssertFalse(remove.exists)
        }
        app.buttons["settings.cancel"].tap()
    }

    func testJevConnectionFailureKeepsSettingsEditable() {
        launch(arguments: ["-prompti-demo", "-prompti-ui-jev-probe", "-prompti-ui-jev-probe-failure",
                           "-prompti-ui-light", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        XCTAssertTrue(app.buttons["home.settings"].waitForExistence(timeout: 5))
        app.buttons["home.settings"].tap()
        let picker = app.buttons["review.provider"]
        for _ in 0..<5 {
            if picker.exists && picker.isHittable { break }
            app.swipeUp()
        }
        picker.tap()
        app.buttons["TypeSafe Jev"].tap()
        let key = app.secureTextFields["review.apiKey"]
        XCTAssertTrue(key.waitForExistence(timeout: 3))
        key.tap()
        key.typeText("fixture-invalid-key")
        app.buttons["review.test"].tap()
        XCTAssertFalse(app.buttons["review.test"].isEnabled)
        attachScreenshot(named: "jev-testing-en-light")
        let status = app.descendants(matching: .any)["review.status"].firstMatch
        let failed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Connection failed"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [failed], timeout: 8), .completed)
        XCTAssertTrue(key.isEnabled)
        XCTAssertFalse(app.buttons["settings.done"].isEnabled)
        XCTAssertTrue(app.buttons["settings.cancel"].isEnabled)
        XCTAssertTrue(app.buttons["review.test"].isEnabled)
        attachScreenshot(named: "jev-failed-en-light")
        app.buttons["settings.cancel"].tap()
    }

    func testReviewVisualState() {
        launch(arguments: ["-prompti-demo"])

        selectTab(systemImage: "arrow.counterclockwise.circle.fill", fallbackIndex: 2)

        XCTAssertTrue(app.descendants(matching: .any)["review.root"].waitForExistence(timeout: 5))
        attachScreenshot(named: "review-empty")
    }

    func testProgressVisualState() {
        launch(arguments: ["-prompti-demo"])

        selectTab(systemImage: "chart.bar.fill", fallbackIndex: 3)

        XCTAssertTrue(app.descendants(matching: .any)["progress.root"].waitForExistence(timeout: 5))
        attachScreenshot(named: "progress-empty")
    }

    func testOnboardingVisualStates() {
        launch(arguments: ["-prompti-demo", "-prompti-onboarding"])

        let continueButton = app.buttons["onboarding.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        attachScreenshot(named: "onboarding-welcome")

        continueButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.destination"].waitForExistence(timeout: 5))
        attachScreenshot(named: "onboarding-destination")

        continueButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.language"].waitForExistence(timeout: 5))
        attachScreenshot(named: "onboarding-language")

        continueButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.model"].waitForExistence(timeout: 5))
        attachScreenshot(named: "onboarding-model")

        continueButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.preferences"].waitForExistence(timeout: 5))
        attachScreenshot(named: "onboarding-preferences")
    }

    func testQuickQuestionStartsSingleQuestion() {
        launch(arguments: ["-prompti-demo"])

        let quickQuestion = app.buttons["home.quickQuestion"]
        XCTAssertTrue(quickQuestion.waitForExistence(timeout: 5))
        quickQuestion.tap()

        // A single approved question opens the session automatically.
        XCTAssertTrue(app.staticTexts["1 / 1"].waitForExistence(timeout: 5))
    }

    func testCompletedPracticeReturnsToSetupWithoutRegenerating() {
        launch(arguments: ["-prompti-demo", "-prompti-practice"])
        startFiveQuestionSession()

        for _ in 0..<5 {
            let options = app.buttons["session.options"]
            XCTAssertTrue(options.waitForExistence(timeout: 5))
            options.tap()
            let skip = app.buttons["session.skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 2))
            skip.tap()
        }

        XCTAssertTrue(app.staticTexts["session.summary"].waitForExistence(timeout: 5))
        attachScreenshot(named: "practice-summary")
        app.buttons["session.done"].tap()

        XCTAssertTrue(app.buttons["practice.generate"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["generation.start"].exists)
    }

    func testPracticeCanBeEndedEarly() {
        launch(arguments: ["-prompti-demo", "-prompti-practice"])
        startFiveQuestionSession()

        let close = app.buttons["session.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        close.tap()

        let confirm = app.buttons["session.confirmExit"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2))
        confirm.firstMatch.tap()

        XCTAssertTrue(app.buttons["practice.generate"].waitForExistence(timeout: 5))
    }

    func testPracticeVisualStates() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-slow-generation", "-prompti-ui-manual-start"])

        let generate = app.buttons["practice.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        attachScreenshot(named: "practice-setup")
        generate.tap()

        let status = app.staticTexts["generation.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 2))
        let generating = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "generating"),
            object: status
        )
        XCTAssertEqual(XCTWaiter.wait(for: [generating], timeout: 2), .completed)
        attachScreenshot(named: "generation-working")

        let start = app.buttons["generation.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 8))
        attachScreenshot(named: "generation-ready")
        start.tap()
        let option = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session.option.")).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        attachScreenshot(named: "practice-question")
        option.tap()
        attachScreenshot(named: "practice-selected")
        app.buttons["session.submit"].tap()
        XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
        XCTAssertFalse(option.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["session.resultBadge"].waitForExistence(timeout: 3))
        attachScreenshot(named: "practice-feedback")
    }

    func testQuickQuestionCancellationReturnsHome() {
        launch(arguments: ["-prompti-demo", "-prompti-ui-slow-generation"])

        let quickQuestion = app.buttons["home.quickQuestion"]
        XCTAssertTrue(quickQuestion.waitForExistence(timeout: 5))
        quickQuestion.tap()

        let cancel = app.buttons["generation.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        cancel.tap()

        XCTAssertTrue(app.buttons["home.destination"].waitForExistence(timeout: 5))
    }

    func testLongAnswersKeepPromptPinnedAndResetForNextQuestion() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-long-answers"])
        startFiveQuestionSession()

        let prompt = app.staticTexts["session.prompt"]
        let answers = app.scrollViews["session.answers"]
        let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session.option."))
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        let promptFrame = prompt.frame
        let submitFrame = app.buttons["session.submit"].frame
        XCTAssertLessThanOrEqual(promptFrame.maxY, answers.frame.minY)
        attachScreenshot(named: "long-answers-top")

        answers.swipeUp(velocity: .slow)
        XCTAssertEqual(prompt.frame.minY, promptFrame.minY, accuracy: 1)
        XCTAssertTrue(prompt.isHittable)
        attachScreenshot(named: "long-answers-middle")

        let last = options.element(boundBy: 3)
        for _ in 0..<6 {
            if answers.frame.contains(last.frame) { break }
            answers.swipeUp(velocity: .slow)
        }
        XCTAssertTrue(answers.frame.contains(last.frame))
        XCTAssertLessThan(last.frame.maxY, submitFrame.minY)
        XCTAssertEqual(prompt.frame.minY, promptFrame.minY, accuracy: 1)
        XCTAssertEqual(app.buttons["session.submit"].frame.minY, submitFrame.minY, accuracy: 1)
        attachScreenshot(named: "long-answers-bottom")

        last.tap()
        app.buttons["session.submit"].tap()
        XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
        let feedbackPromptFrame = prompt.frame
        answers.swipeUp(velocity: .slow)
        XCTAssertTrue(prompt.isHittable)
        XCTAssertEqual(prompt.frame.minY, feedbackPromptFrame.minY, accuracy: 1)
        attachScreenshot(named: "long-answers-feedback")

        app.buttons["session.next"].tap()
        XCTAssertTrue(app.staticTexts["2 / 5"].waitForExistence(timeout: 5))
        XCTAssertTrue(answers.frame.contains(options.firstMatch.frame))
        XCTAssertTrue(options.firstMatch.isHittable)
        attachScreenshot(named: "short-answers-reset")
    }

    func testPracticeDestinationTracksHomeSelection() {
        launch(arguments: ["-prompti-demo", "-prompti-practice"])
        XCTAssertTrue(app.buttons["practice.generate"].waitForExistence(timeout: 5))

        selectTab(systemImage: "sun.max.fill", fallbackIndex: 0)
        app.buttons["home.destination"].tap()

        let osaka = app.buttons["destination.osaka"]
        XCTAssertTrue(osaka.waitForExistence(timeout: 5))
        osaka.tap()

        selectTab(systemImage: "text.book.closed.fill", fallbackIndex: 1)
        XCTAssertTrue(app.descendants(matching: .any)["practice.destination.osaka"].waitForExistence(timeout: 5))
    }

    func testGenerationPartialSuccessVisualState() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-partial-generation", "-prompti-ui-manual-start"])
        app.buttons["practice.generate"].tap()

        XCTAssertTrue(app.buttons["generation.start"].waitForExistence(timeout: 5))
        let manifest = app.descendants(matching: .any)["generation.manifest"]
        XCTAssertTrue(manifest.waitForExistence(timeout: 2))
        XCTAssertTrue(["3 of 5", "3 / 5"].contains(manifest.value as? String ?? ""))
        attachScreenshot(named: "generation-partial")
    }

    func testGenerationFailureVisualState() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-generation-error"])
        app.buttons["practice.generate"].tap()

        XCTAssertTrue(app.buttons["generation.recovery.retry"].waitForExistence(timeout: 5))
        attachScreenshot(named: "generation-failure")
    }

    func testFailedTopUpKeepsPreparedQuestionsAvailable() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-partial-generation", "-prompti-ui-fill-error", "-prompti-ui-manual-start"])
        XCTAssertTrue(app.buttons["practice.generate"].waitForExistence(timeout: 5))
        app.buttons["practice.generate"].tap()
        XCTAssertTrue(app.buttons["generation.fillRemaining"].waitForExistence(timeout: 5))
        app.buttons["generation.fillRemaining"].tap()
        let start = app.buttons["generation.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["1 / 5"].waitForExistence(timeout: 5))
    }

    func testScoredAnswerCannotAlsoBeSkipped() {
        launch(arguments: ["-prompti-demo", "-prompti-practice"])
        startFiveQuestionSession()
        let choice = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session.option.")).firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: 5))
        choice.tap()
        app.buttons["session.submit"].tap()
        XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
        app.buttons["session.options"].tap()
        let skip = app.buttons["session.skip"]
        XCTAssertTrue(skip.waitForExistence(timeout: 2))
        XCTAssertFalse(skip.isEnabled)
    }

    func testSpokenPermissionFallbackShowsSample() {
        launch(arguments: [
            "-prompti-demo",
            "-prompti-practice",
            "-prompti-ui-spoken-question",
            "-prompti-ui-speech-denied"
        ])
        startFiveQuestionSession()

        let submit = app.buttons["session.submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertTrue(submit.isEnabled)
        submit.tap()

        XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
        attachScreenshot(named: "speech-fallback")
    }

    func testReviewAndProgressWithData() {
        launch(arguments: ["-prompti-demo", "-prompti-practice"])
        startFiveQuestionSession()

        let optionPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "session.option.")
        let wrongOption = app.buttons.matching(optionPredicate).element(boundBy: 1)
        XCTAssertTrue(wrongOption.waitForExistence(timeout: 5))
        wrongOption.tap()
        app.buttons["session.submit"].tap()
        app.buttons["session.next"].tap()

        for _ in 0..<4 {
            let options = app.buttons["session.options"]
            XCTAssertTrue(options.waitForExistence(timeout: 5))
            options.tap()
            let skip = app.buttons["session.skip"]
            XCTAssertTrue(skip.waitForExistence(timeout: 2))
            skip.tap()
        }

        XCTAssertTrue(app.buttons["session.done"].waitForExistence(timeout: 5))
        attachScreenshot(named: "practice-summary-incorrect")
        app.buttons["session.done"].tap()

        selectTab(systemImage: "arrow.counterclockwise.circle.fill", fallbackIndex: 2)
        let reviewQuestion = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "review.question.")
        ).firstMatch
        XCTAssertTrue(reviewQuestion.waitForExistence(timeout: 5))
        attachScreenshot(named: "review-with-data")

        reviewQuestion.tap()
        let correctOption = app.buttons.matching(optionPredicate).element(boundBy: 0)
        XCTAssertTrue(correctOption.waitForExistence(timeout: 5))
        correctOption.tap()
        app.buttons["session.submit"].tap()
        XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
        app.buttons["session.next"].tap()
        XCTAssertTrue(app.buttons["session.done"].waitForExistence(timeout: 5))
        XCTAssertTrue(["All correct!", "全部答对！"].contains(app.staticTexts["session.summary"].label))
        // Capture the resting layout after the finite celebration has finished.
        Thread.sleep(forTimeInterval: 2)
        attachScreenshot(named: "practice-summary-correct")
        app.buttons["session.done"].tap()
        XCTAssertTrue(app.buttons["review.filters"].waitForExistence(timeout: 5))
        XCTAssertFalse(reviewQuestion.exists)

        selectTab(systemImage: "chart.bar.fill", fallbackIndex: 3)
        XCTAssertTrue(app.descendants(matching: .any)["progress.metrics"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["progress.mix"].waitForExistence(timeout: 5))
        attachScreenshot(named: "progress-with-data")
    }

    func testReviewDeletionEnglishLight() { verifyReviewDeletion(language: "en", style: "Light") }
    func testReviewDeletionChineseDark() { verifyReviewDeletion(language: "zh-Hans", style: "Dark") }

    private func verifyReviewDeletion(language: String, style: String) {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-AppleLanguages", "(\(language))",
                           "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                           style == "Dark" ? "-prompti-ui-dark" : "-prompti-ui-light"])
        startFiveQuestionSession()
        let options = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "session.option."))
        for index in 0..<5 {
            if index == 2 || index == 4 {
                XCTAssertTrue(app.buttons["session.options"].waitForExistence(timeout: 5))
                app.buttons["session.options"].tap()
                app.buttons["session.skip"].tap()
            } else {
                let option = options.element(boundBy: index == 3 ? 0 : 1)
                XCTAssertTrue(option.waitForExistence(timeout: 5))
                option.tap()
                app.buttons["session.submit"].tap()
                XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
                app.buttons["session.next"].tap()
            }
        }
        XCTAssertTrue(app.buttons["session.done"].waitForExistence(timeout: 5))
        app.buttons["session.done"].tap()
        selectTab(systemImage: "arrow.counterclockwise.circle.fill", fallbackIndex: 2)

        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.question."))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        attachScreenshot(named: "review-mistakes-\(language)-\(style)")

        app.buttons["review.clearAll"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3))
        attachScreenshot(named: "review-clear-confirmation-\(language)-\(style)")
        app.alerts.buttons[language == "en" ? "Cancel" : "取消"].tap()
        XCTAssertEqual(rows.count, 2)

        let removedID = rows.firstMatch.identifier
        rows.firstMatch.swipeLeft()
        let delete = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "review.delete.")).firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        XCTAssertEqual(delete.label, language == "en" ? "Delete" : "删除")
        XCTAssertEqual(rows.count, 2) // Swiping alone must never delete a record.
        attachScreenshot(named: "review-swipe-delete-\(language)-\(style)")
        delete.tap()
        XCTAssertFalse(app.buttons[removedID].exists)
        XCTAssertEqual(rows.count, 1)

        app.buttons["review.clearAll"].tap()
        app.alerts.buttons[language == "en" ? "Clear all" : "一键清空"].tap()
        XCTAssertTrue(rows.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["review.clearAll"].isEnabled)
        attachScreenshot(named: "review-mistakes-cleared-\(language)-\(style)")

        selectTab(systemImage: "chart.bar.fill", fallbackIndex: 3)
        XCTAssertTrue(app.descendants(matching: .any)["progress.metrics"].waitForExistence(timeout: 5))
        selectTab(systemImage: "arrow.counterclockwise.circle.fill", fallbackIndex: 2)
        app.buttons["review.mode.history"].tap()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(rows.count, 3) // Correct and skipped questions survive clearing mistakes.
        rows.firstMatch.swipeLeft()
        XCTAssertTrue(delete.waitForExistence(timeout: 3))
        attachScreenshot(named: "review-history-swipe-\(language)-\(style)")
        delete.tap()
        XCTAssertEqual(rows.count, 2)
        if language == "en" {
            app.buttons["review.filters"].tap()
            app.buttons["Dining"].tap()
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(app.buttons["review.clearAll"].label, "Clear filtered")
            attachScreenshot(named: "review-filtered-\(language)-\(style)")
            app.buttons["review.clearAll"].tap()
            app.alerts.buttons["Clear all"].tap()
            XCTAssertTrue(rows.firstMatch.waitForNonExistence(timeout: 3))
            XCTAssertFalse(app.buttons["review.clearAll"].isEnabled)
            app.buttons["Clear"].tap()
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 3))
            XCTAssertEqual(rows.count, 1) // The question outside the filter stays saved.
        }
        app.buttons["review.clearAll"].tap()
        app.alerts.buttons[language == "en" ? "Clear all" : "一键清空"].tap()
        XCTAssertTrue(rows.firstMatch.waitForNonExistence(timeout: 3))
        XCTAssertFalse(app.buttons["review.clearAll"].isEnabled)
        attachScreenshot(named: "review-history-cleared-\(language)-\(style)")

        selectTab(systemImage: "chart.bar.fill", fallbackIndex: 3)
        XCTAssertTrue(app.descendants(matching: .any)["progress.root"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["progress.metrics"].exists)
    }

    func testHomeStartsDefaultPracticeSet() {
        launch(arguments: ["-prompti-demo"])
        let start = app.buttons["home.startPractice"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        // Enough approved questions open the session automatically; the rest fill in.
        XCTAssertTrue(app.staticTexts["1 / 5"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["generation.start"].exists)
    }

    func testPracticeAutoStartsWhileRemainingQuestionsFill() {
        verifyFirstQuestionStarts(language: "en")
    }

    func testPracticeAutoStartsWithFirstQuestionChinese() {
        verifyFirstQuestionStarts(language: "zh-Hans")
    }

    private func verifyFirstQuestionStarts(language: String) {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-auto-fill",
                           "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN"])
        let generate = app.buttons["practice.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        // The fixture emits exactly one approved question, then holds the rest.
        XCTAssertTrue(app.staticTexts["1 / 5"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["session.preparationStatus"].exists)
        XCTAssertTrue(app.buttons["session.submit"].exists)
        attachScreenshot(named: "first-question-\(language)")
    }

    func testModelSetupRequiresVerifiedConnection() {
        launch(arguments: ["-prompti-onboarding"])
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<3 { next.tap() }
        XCTAssertTrue(app.buttons["model.connect"].waitForExistence(timeout: 5))
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(app.buttons["model.connect"].isEnabled)
        let key = app.secureTextFields["model.apiKey"]
        XCTAssertTrue(key.exists)
        key.tap()
        key.typeText("fixture-key-not-sent")
        XCTAssertTrue(app.buttons["model.connect"].isEnabled)
        XCTAssertFalse(next.isEnabled)
    }

    func testWelcomeWithDefaultLayout() {
        launch(arguments: ["-prompti-onboarding", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"])
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertTrue(next.isHittable)
        attachScreenshot(named: "welcome-default")
        next.tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.destination"].waitForExistence(timeout: 5))
    }

    func testLocalizedModelSelectionInChinese() {
        checkLocalizedModelSelection(language: "zh-Hans", locale: "zh_CN")
    }

    func testLocalizedModelSelectionInEnglish() {
        checkLocalizedModelSelection(language: "en", locale: "en_US")
    }

    private func checkLocalizedModelSelection(language: String, locale: String) {
        launch(arguments: ["-prompti-onboarding", language == "en" ? "-prompti-ui-light" : "-prompti-ui-dark",
                           "-AppleLanguages", "(\(language))", "-AppleLocale", locale])
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<3 { next.tap() }
        let selection = app.buttons["model.selection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["model.advanced"].exists)
        XCTAssertTrue(selection.label.contains("GPT-5.6 Luna"))
        XCTAssertFalse(next.isEnabled)
        attachScreenshot(named: "model-\(language)")
        selection.tap()
        // UIKit menus expose their localized title rather than the SwiftUI identifier.
        let gemini = app.buttons["Gemini 3.8 Flash"]
        XCTAssertTrue(gemini.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["DeepSeek V4.1 Flash"].exists)
        attachScreenshot(named: "model-options-\(language)")
        gemini.tap()
        XCTAssertTrue(selection.label.contains("Gemini 3.8 Flash"))
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(app.buttons["model.connectWithCode"].exists)
        XCTAssertFalse(app.textFields["model.endpoint"].exists)
        let key = app.secureTextFields["model.apiKey"]
        XCTAssertTrue(key.exists)
        XCTAssertFalse(app.buttons["model.connect"].isEnabled)
        key.tap()
        key.typeText("fixture-key-not-sent")
        XCTAssertTrue(app.buttons["model.connect"].isEnabled)
        XCTAssertFalse(next.isEnabled)

        selection.tap()
        app.buttons[language == "en" ? "Enter model ID" : "输入模型 ID"].tap()
        let modelID = app.textFields["model.customID"]
        XCTAssertTrue(modelID.waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["model.connect"].isEnabled)
        modelID.tap()
        modelID.typeText("my-custom-model\n")
        XCTAssertEqual(modelID.value as? String, "my-custom-model")
        XCTAssertTrue(app.buttons["model.connect"].isEnabled)
        XCTAssertFalse(next.isEnabled)
        attachScreenshot(named: "model-custom-\(language)")

        app.buttons["model.provider"].tap()
        app.buttons["Google Gemini"].tap()
        XCTAssertTrue(selection.label.contains("Gemini 3.8 Flash"))
        XCTAssertFalse(app.textFields["model.endpoint"].exists)
        XCTAssertFalse(app.textFields["model.customID"].exists)
        XCTAssertFalse(app.buttons["model.connect"].isEnabled)
        XCTAssertFalse(next.isEnabled)
        attachScreenshot(named: "gemini-\(language)")

        app.buttons["model.provider"].tap()
        app.buttons[language == "en" ? "OpenAI Chat / Compatible" : "OpenAI Chat / 兼容服务"].tap()
        XCTAssertTrue(app.textFields["model.endpoint"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textFields["model.customID"].exists)
        XCTAssertFalse(app.buttons["model.connect"].isEnabled)
        attachScreenshot(named: "model-compatible-\(language)")
    }

    func testChineseDestinationSearchAndPractice() {
        launch(arguments: ["-prompti-demo", "-prompti-ui-manual-start", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"])
        XCTAssertTrue(app.buttons["home.destination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["东京"].exists)
        attachScreenshot(named: "home-zh-Hans")
        app.buttons["home.destination"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.tap()
        search.typeText("北京")
        let beijing = app.buttons["destination.beijing"]
        XCTAssertTrue(beijing.waitForExistence(timeout: 3))
        attachScreenshot(named: "destination-search-zh-Hans")
        beijing.tap()
        XCTAssertTrue(app.staticTexts["北京"].waitForExistence(timeout: 3))
        app.buttons["home.startPractice"].tap()
        XCTAssertTrue(app.buttons["generation.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["北京"].exists)
        attachScreenshot(named: "generation-zh-Hans")
    }

    func testMultipleBlanksRequireEveryAnswer() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-multiple-blanks"])
        startFiveQuestionSession()
        let submit = app.buttons["session.submit"]
        XCTAssertFalse(submit.isEnabled)
        attachScreenshot(named: "multiple-blanks-unanswered")
        app.buttons["session.blank.0.0"].tap()
        XCTAssertFalse(submit.isEnabled)
        attachScreenshot(named: "multiple-blanks-partial")
        let second = app.buttons["session.blank.1.0"]
        if !second.isHittable { app.swipeUp() }
        second.tap()
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session.blank.0.0"].isEnabled)
        XCTAssertFalse(second.isEnabled)
        attachScreenshot(named: "multiple-blanks-feedback")
    }

    func testTranscriptCanBeEditedWithoutMicrophonePermission() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-spoken-question", "-prompti-ui-speech-denied"])
        startFiveQuestionSession()
        let transcript = app.descendants(matching: .any)["session.transcript"].firstMatch
        XCTAssertTrue(transcript.waitForExistence(timeout: 5))
        transcript.tap()
        transcript.typeText("Could you tell me the way to Shinjuku?")
        attachScreenshot(named: "speech-edited")
        app.buttons["session.submit"].tap()
        XCTAssertTrue(app.buttons["session.next"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.buttons["session.hearSample"].waitForExistence(timeout: 5))
        attachScreenshot(named: "speech-feedback")
    }

    func testWaitingCanFinishEnglishLight() { verifyWaitingCanFinish(language: "en", style: "Light") }
    func testWaitingCanFinishChineseDark() { verifyWaitingCanFinish(language: "zh-Hans", style: "Dark") }

    private func verifyWaitingCanFinish(language: String, style: String) {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-auto-fill", "-prompti-ui-waiting",
                           "-AppleLanguages", "(\(language))", "-AppleLocale", language == "en" ? "en_US" : "zh_CN",
                           style == "Dark" ? "-prompti-ui-dark" : "-prompti-ui-light"])
        startFiveQuestionSession()
        XCTAssertTrue(app.buttons["session.pauseFill"].exists)
        attachScreenshot(named: "preparation-active-\(language)")
        let prompt = app.staticTexts["session.prompt"].label
        app.buttons["session.pauseFill"].tap()
        XCTAssertTrue(app.buttons["session.retryFill"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.staticTexts["session.prompt"].label, prompt)
        attachScreenshot(named: "preparation-paused-\(language)")
        app.buttons["session.retryFill"].tap()
        XCTAssertTrue(app.buttons["session.pauseFill"].waitForExistence(timeout: 3))
        // The retry can prepare one extra question immediately. Skip all ready questions.
        for _ in 0..<2 {
            app.buttons["session.options"].tap()
            app.buttons["session.skip"].tap()
        }
        XCTAssertTrue(app.buttons["session.finishPartial"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["session.retryFill"].exists)
        attachScreenshot(named: "preparation-waiting-\(language)")
        app.buttons["session.finishPartial"].tap()
        XCTAssertTrue(app.staticTexts["session.summary"].waitForExistence(timeout: 3))
    }

    func testBackgroundDoesNotRestartPreparation() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-auto-fill", "-prompti-ui-waiting"])
        startFiveQuestionSession()
        let prompt = app.staticTexts["session.prompt"].label
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["session.retryFill"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["session.pauseFill"].exists)
        XCTAssertEqual(app.staticTexts["session.prompt"].label, prompt)
        XCTAssertTrue(app.staticTexts["1 / 5"].exists)
    }

    func testTopUpKeepsStartAvailable() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-partial-generation",
                           "-prompti-ui-slow-generation", "-prompti-ui-manual-start"])
        app.buttons["practice.generate"].tap()
        let fill = app.buttons["generation.fillRemaining"]
        XCTAssertTrue(fill.waitForExistence(timeout: 8))
        fill.tap()
        XCTAssertTrue(app.buttons["generation.pause"].waitForExistence(timeout: 2))
        let start = app.buttons["generation.start"]
        XCTAssertTrue(start.isEnabled)
        attachScreenshot(named: "top-up-start-available")
        start.tap()
        XCTAssertTrue(app.buttons["session.submit"].waitForExistence(timeout: 5))
    }

    func testAutomaticFillPreservesCurrentQuestion() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-auto-fill"])
        let generate = app.buttons["practice.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        // The first approved batch opens the session while the rest keep filling.
        XCTAssertTrue(app.staticTexts["1 / 5"].waitForExistence(timeout: 5))
        let preparing = app.staticTexts["session.preparationStatus"]
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: preparing)
        XCTAssertEqual(XCTWaiter.wait(for: [filled], timeout: 8), .completed)
        XCTAssertTrue(app.staticTexts["1 / 5"].exists)
        XCTAssertTrue(app.buttons["session.submit"].exists)
    }

    func testAutomaticFillFailureAllowsPartialCompletion() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-partial-generation", "-prompti-ui-fill-error"])
        app.buttons["practice.generate"].tap()
        // A partial set still opens the session automatically.
        XCTAssertTrue(app.buttons["session.options"].waitForExistence(timeout: 8))
        for _ in 0..<3 {
            app.buttons["session.options"].tap()
            app.buttons["session.skip"].tap()
        }
        XCTAssertTrue(app.buttons["session.retryFill"].waitForExistence(timeout: 5))
        app.buttons["session.finishPartial"].tap()
        XCTAssertTrue(app.staticTexts["session.summary"].waitForExistence(timeout: 5))
        attachScreenshot(named: "practice-summary-partial")
    }

    func testGenerationModeAndBroadScenesEnglish() { verifyGenerationModeAndBroadScenes(language: "en") }
    func testGenerationModeAndBroadScenesChinese() { verifyGenerationModeAndBroadScenes(language: "zh-Hans") }

    private func verifyGenerationModeAndBroadScenes(language: String) {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-AppleLanguages", "(\(language))",
                           "-AppleLocale", language == "en" ? "en_US" : "zh_CN"])
        XCTAssertTrue(app.buttons["practice.scene.dining"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["practice.sceneExpansion"].exists)
        for id in ["tokyo-ramen", "tokyo-sushi", "tokyo-ic", "cafe", "desserts", "market"] {
            XCTAssertFalse(app.buttons["practice.scene.\(id)"].exists)
        }
        attachScreenshot(named: "tokyo-scenes-\(language)")
        app.buttons["practice.changeDestination"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Singapore")
        app.buttons["destination.singapore"].tap()
        XCTAssertTrue(app.buttons["practice.scene.dining"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["practice.scene.transit"].exists)
        for id in ["singapore-highlights", "singapore-bak-kut-teh", "singapore-durian", "singapore-dessert", "singapore-drinks"] {
            XCTAssertFalse(app.buttons["practice.scene.\(id)"].exists)
        }
        attachScreenshot(named: "singapore-scenes-\(language)")
        app.buttons["practice.changeDestination"].tap()
        let parisSearch = app.searchFields.firstMatch
        XCTAssertTrue(parisSearch.waitForExistence(timeout: 5))
        parisSearch.tap()
        parisSearch.typeText("Paris")
        app.buttons["destination.paris"].tap()
        XCTAssertTrue(app.buttons["practice.scene.dining"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["practice.sceneExpansion"].exists)
        XCTAssertFalse(app.buttons["practice.scene.paris-highlights"].exists)
        attachScreenshot(named: "paris-scenes-\(language)")
        let control = app.segmentedControls["practice.generationMode"]
        for _ in 0..<6 {
            if control.exists && control.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(control.isHittable)
        control.buttons[language == "en" ? "Token-saving" : "节省 Token"].tap()
        attachScreenshot(named: "generation-efficient-\(language)")
        control.buttons[language == "en" ? "Flexible" : "宽松模式"].tap()
        attachScreenshot(named: "generation-flexible-\(language)")
        app.buttons["practice.generate"].tap()
        XCTAssertTrue(app.buttons["session.submit"].waitForExistence(timeout: 8))
        attachScreenshot(named: "generation-session-\(language)")
    }

    private func launch(arguments: [String]) {
        app = XCUIApplication()
        app.launchArguments = ["-prompti-ui-clean-data"] + arguments
        app.launch()
    }

    private func startFiveQuestionSession() {
        let generate = app.buttons["practice.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()

        // Sessions open automatically once the first approved questions arrive.
        XCTAssertTrue(app.buttons["session.options"].waitForExistence(timeout: 8))
    }

    private func selectTab(systemImage: String, fallbackIndex: Int) {
        let adaptiveTab = app.buttons[systemImage].firstMatch
        if adaptiveTab.waitForExistence(timeout: 2) {
            adaptiveTab.tap()
            return
        }

        let tabBarButton = app.tabBars.firstMatch.buttons.element(boundBy: fallbackIndex)
        XCTAssertTrue(tabBarButton.waitForExistence(timeout: 5))
        tabBarButton.tap()
    }

    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

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

        let generationStart = app.buttons["generation.start"]
        if generationStart.waitForExistence(timeout: 3) {
            generationStart.tap()
        }

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
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-slow-generation"])

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
        XCTAssertTrue(start.waitForExistence(timeout: 5))
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
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-partial-generation"])
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
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-partial-generation", "-prompti-ui-fill-error"])
        XCTAssertTrue(app.buttons["practice.generate"].waitForExistence(timeout: 5))
        app.buttons["practice.generate"].tap()
        XCTAssertTrue(app.buttons["generation.fillRemaining"].waitForExistence(timeout: 5))
        app.buttons["generation.fillRemaining"].tap()
        let startPrepared = app.buttons["generation.startPrepared"]
        XCTAssertTrue(startPrepared.waitForExistence(timeout: 5))
        startPrepared.tap()
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

    func testHomeStartsDefaultPracticeSet() {
        launch(arguments: ["-prompti-demo"])
        let start = app.buttons["home.startPractice"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        let ready = app.buttons["generation.start"]
        XCTAssertTrue(ready.waitForExistence(timeout: 5))
        ready.tap()
        XCTAssertTrue(app.staticTexts["1 / 5"].waitForExistence(timeout: 5))
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
        launch(arguments: ["-prompti-onboarding", "-AppleLanguages", "(\(language))", "-AppleLocale", locale])
        let next = app.buttons["onboarding.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        for _ in 0..<3 { next.tap() }
        let selection = app.buttons["model.selection"]
        XCTAssertTrue(selection.waitForExistence(timeout: 5))
        XCTAssertTrue(selection.label.contains("DeepSeek V4 Flash 0731"))
        XCTAssertFalse(next.isEnabled)
        attachScreenshot(named: "model-\(language)")
        selection.tap()
        // UIKit menus expose their localized title rather than the SwiftUI identifier.
        let gemini = app.buttons["Gemini 3.8 Flash"]
        XCTAssertTrue(gemini.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["DeepSeek V4 Flash 0731"].exists)
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
        launch(arguments: ["-prompti-demo", "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"])
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
        app.buttons["session.blank.0.0"].tap()
        XCTAssertFalse(submit.isEnabled)
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

    func testAutomaticFillPreservesCurrentQuestion() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-auto-fill"])
        let generate = app.buttons["practice.generate"]
        XCTAssertTrue(generate.waitForExistence(timeout: 5))
        generate.tap()
        let start = app.buttons["generation.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        XCTAssertTrue(app.staticTexts["1 / 5"].waitForExistence(timeout: 2))
        let preparing = app.staticTexts["session.preparationStatus"]
        let filled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: preparing)
        XCTAssertEqual(XCTWaiter.wait(for: [filled], timeout: 6), .completed)
        XCTAssertTrue(app.staticTexts["1 / 5"].exists)
        XCTAssertTrue(app.buttons["session.submit"].exists)
    }

    func testAutomaticFillFailureAllowsPartialCompletion() {
        launch(arguments: ["-prompti-demo", "-prompti-practice", "-prompti-ui-partial-generation", "-prompti-ui-fill-error"])
        app.buttons["practice.generate"].tap()
        let start = app.buttons["generation.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
        for _ in 0..<3 {
            app.buttons["session.options"].tap()
            app.buttons["session.skip"].tap()
        }
        XCTAssertTrue(app.buttons["session.retryFill"].waitForExistence(timeout: 5))
        app.buttons["session.finishPartial"].tap()
        XCTAssertTrue(app.staticTexts["session.summary"].waitForExistence(timeout: 5))
        attachScreenshot(named: "practice-summary-partial")
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

        let start = app.buttons["generation.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()
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

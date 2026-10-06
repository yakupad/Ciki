import XCTest

/// Kalem düzenleme akışları: yazarken tutar biçimleme, klavye araç çubuğu ve tutar değişikliği.
@MainActor
final class EditingTests: XCTestCase {
    private func launchOnItems() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-loadSampleData", "-AppleLanguages", "(tr)", "-startTab", "3"]
        app.launch()
        return app
    }

    func testAmountChangeAndLiveFormatting() throws {
        let app = launchOnItems()
        // Örnek veride "Kira" her ay tekrarlayan bir kalem.
        let rent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kira,'")).firstMatch
        XCTAssertTrue(rent.waitForExistence(timeout: 10))
        rent.tap()
        XCTAssertTrue(app.navigationBars["Kalemi düzenle"].waitForExistence(timeout: 5), "Kalem düzenleyici açılmalı")

        // Bölüm formun altında; görünene kadar kaydırılır.
        let addChange = app.buttons["Tutar değişikliği ekle"]
        for _ in 0..<5 where !addChange.isHittable { app.swipeUp() }

        XCTAssertTrue(addChange.waitForExistence(timeout: 5))
        addChange.tap()
        XCTAssertTrue(app.staticTexts["Yeni tutar"].waitForExistence(timeout: 5))

        // Yeni değişikliğin tutar alanı: önce temizlenir, sonra yazılır.
        let fields = app.textFields.allElementsBoundByIndex
        let field = try XCTUnwrap(fields.last)
        field.tap()
        let clear = app.buttons["Temizle"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5), "Klavye araç çubuğu görünmeli")
        clear.tap()
        field.typeText("27500")
        XCTAssertEqual(field.value as? String, "27.500")
        app.buttons["Üç sıfır ekle"].tap()
        XCTAssertEqual(field.value as? String, "27.500.000")

        // Boş bir yere dokununca klavye kapanır.
        app.staticTexts["Yeni tutar"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tutar değişikliği"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

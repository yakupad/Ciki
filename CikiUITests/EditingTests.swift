import XCTest

/// Kalem düzenleme akışları: yazarken tutar biçimleme, klavyenin kapanması ve tutar değişikliği.
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
        // İmleç metnin sonuna gelsin diye alanın sağ ucuna dokunulur.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap()
        // Önceki tutar silinir, yenisi yazılır.
        let existing = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        field.typeText("27500")
        XCTAssertEqual(field.value as? String, "27.500")
        // Geri silme son rakamı siler ve binlik ayırıcı yeniden yerleşir.
        field.typeText(XCUIKeyboardKey.delete.rawValue)
        XCTAssertEqual(field.value as? String, "2.750")

        // Boş bir yere dokununca klavye kapanır.
        app.staticTexts["Yeni tutar"].tap()
        XCTAssertFalse(app.keyboards.firstMatch.waitForExistence(timeout: 2))

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Tutar değişikliği"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testOneOffExpenseInOneStep() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-loadSampleData", "-AppleLanguages", "(tr)", "-startTab", "1"]
        app.launch()

        let newEntry = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Yeni kayıt'")).firstMatch
        XCTAssertTrue(newEntry.waitForExistence(timeout: 10))
        newEntry.tap()
        XCTAssertTrue(app.navigationBars["Yeni kayıt"].waitForExistence(timeout: 5))

        // Tutar alanı açılışta odaklıdır.
        app.typeText("3450")
        app.buttons["Tek seferlik"].tap()
        let name = app.textFields["Ör. Kombi tamiri"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Kombi tamiri")
        app.buttons["Kaydet"].tap()

        // Kayıt bu ayın listesinde, "Diğer giderler" altında görünür; liste aşağı kaydırılır.
        XCTAssertTrue(app.navigationBars["Yeni kayıt"].waitForNonExistence(timeout: 5), "Kayıt ekranı kapanmalı")
        let row = app.staticTexts["Kombi tamiri"]
        for _ in 0..<8 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.exists)
        XCTAssertTrue(app.staticTexts["−3.450 ₺"].exists)
    }

    /// iCloud'dan gelen değişiklik taklit edilir; Kalemler listesi açık ekranda kendiliğinden güncellenmeli.
    func testItemsListUpdatesForRemoteChanges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-loadSampleData", "-simulateRemoteChange", "-AppleLanguages", "(tr)", "-startTab", "3"]
        app.launch()
        let rent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kira,'")).firstMatch
        XCTAssertTrue(rent.waitForExistence(timeout: 10))
        XCTAssertTrue(rent.label.contains("24.000"), rent.label)
        let updated = NSPredicate(format: "label CONTAINS '26.000'")
        expectation(for: updated, evaluatedWith: rent)
        waitForExpectations(timeout: 15)
    }
}

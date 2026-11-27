import XCTest
@testable import PokeTokenBar

final class PreorderCopyTests: XCTestCase {
    func test_arrivalPicksTheKoreanParticleAndNeverShowsOdds() {
        XCTAssertEqual(L(.ko).notifPreorderBody("구프"), "예약한 구프가 도착했어요")
        XCTAssertEqual(L(.ko).notifPreorderBody("건담 Mk-II(에우고)"), "예약한 건담 Mk-II(에우고)이(가) 도착했어요")
        for lang in AppLanguage.allCases { XCTAssertFalse(L(lang).notifPreorderBody("A").contains("1/")) }
    }

    func test_statusSaysThisBoxWhileHeldAndNextBoxWhileBuilding() {
        let l = L(.ko)
        XCTAssertEqual(l.preorderStatusOdds(box: 2, nextBox: false), "이번 박스 25% (2/4)")
        XCTAssertEqual(l.preorderStatusOdds(box: 2, nextBox: true), "다음 박스 25% (2/4)")
        XCTAssertEqual(l.preorderStatusGuaranteed(nextBox: false), "이번 박스에 확정")
        XCTAssertEqual(l.preorderStatusGuaranteed(nextBox: true), "다음 박스에 확정")
    }
}

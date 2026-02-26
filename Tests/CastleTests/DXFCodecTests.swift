import XCTest
@testable import Castle

final class DXFCodecTests: XCTestCase {
    func testParseLineAndCircle() {
        let input = """
        0
        SECTION
        2
        ENTITIES
        0
        LINE
        8
        walls
        10
        1
        20
        2
        11
        3
        21
        4
        0
        CIRCLE
        8
        columns
        10
        5
        20
        6
        40
        7
        0
        ENDSEC
        0
        EOF
        """
        let doc = DXFCodec.parse(text: input, defaultName: "Sample")
        XCTAssertEqual(doc.entities.count, 2)
        XCTAssertEqual(doc.units, .millimeters)
    }

    func testSerializeProducesEndMarker() {
        let doc = DXFDocument(
            name: "T",
            units: .millimeters,
            layerStyles: [:],
            entities: [.line(start: .init(x: 0, y: 0), end: .init(x: 10, y: 10), layer: "0", style: .default)]
        )
        let out = DXFCodec.serialize(document: doc)
        XCTAssertTrue(out.contains("\n0\nEOF\n"))
        XCTAssertTrue(out.contains("\n0\nLINE\n"))
        XCTAssertTrue(out.contains("\n9\n$INSUNITS\n70\n4\n"))
    }

    func testParseInsUnitsFromHeader() {
        let input = """
        0
        SECTION
        2
        HEADER
        9
        $INSUNITS
        70
        1
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        ENDSEC
        0
        EOF
        """
        let doc = DXFCodec.parse(text: input, defaultName: "Units")
        XCTAssertEqual(doc.units, .inches)
    }

    func testParseLWPolylineAndInsertBlock() {
        let input = """
        0
        SECTION
        2
        BLOCKS
        0
        BLOCK
        2
        BOX
        0
        LINE
        8
        walls
        10
        0
        20
        0
        11
        10
        21
        0
        0
        ENDBLK
        0
        ENDSEC
        0
        SECTION
        2
        ENTITIES
        0
        LWPOLYLINE
        8
        walls
        70
        1
        10
        0
        20
        0
        10
        10
        20
        0
        10
        10
        20
        10
        0
        INSERT
        2
        BOX
        10
        50
        20
        50
        0
        ENDSEC
        0
        EOF
        """
        let doc = DXFCodec.parse(text: input, defaultName: "X")
        XCTAssertEqual(doc.entities.count, 4)
    }
}

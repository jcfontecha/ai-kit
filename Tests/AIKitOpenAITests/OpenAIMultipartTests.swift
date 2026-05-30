import XCTest
@testable import AIKitOpenAI

final class OpenAIMultipartTests: XCTestCase {
  func testEncodesFieldsAndFiles() {
    var form = OpenAIMultipartForm(boundary: "BOUNDARY")
    form.addField(name: "model", value: "gpt-image-1")
    form.addFile(
      name: "image",
      filename: "image-0.png",
      contentType: "image/png",
      data: Data([0x01, 0x02])
    )

    let data = form.encode()
    let text = String(decoding: data, as: UTF8.self)

    XCTAssertTrue(form.contentType.contains("boundary=BOUNDARY"))
    XCTAssertTrue(text.contains("--BOUNDARY\r\n"))
    XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\ngpt-image-1\r\n"))
    XCTAssertTrue(text.contains("Content-Disposition: form-data; name=\"image\"; filename=\"image-0.png\"\r\n"))
    XCTAssertTrue(text.contains("Content-Type: image/png\r\n\r\n"))
    XCTAssertTrue(text.hasSuffix("--BOUNDARY--\r\n"))

    // The raw file bytes must survive intact between the header and trailing CRLF.
    XCTAssertTrue(data.range(of: Data([0x01, 0x02])) != nil)
  }
}

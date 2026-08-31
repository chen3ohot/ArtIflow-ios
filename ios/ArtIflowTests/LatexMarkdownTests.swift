import XCTest
@testable import ArtIflow

final class LatexMarkdownTests: XCTestCase {
    func testDetectsSingleDollarInlineFormula() {
        XCTAssertTrue(containsLatexMarkdown("抛物线顶点可以写成 $y=a(x-h)^2+k$ 的形式"))
    }

    func testDetectsDoubleDollarInlineFormula() {
        XCTAssertTrue(containsLatexMarkdown("欧拉公式 $$e^{i\\pi}+1=0$$ 很经典"))
    }

    func testDetectsDoubleDollarBlockFormula() {
        let markdown = """
        先看这个式子：

        $$
        x_1 = \\frac{-b + \\sqrt{b^2 - 4ac}}{2a}
        $$
        """
        XCTAssertTrue(containsLatexMarkdown(markdown))
    }

    func testDetectsSlashBracketAndSlashParenForms() {
        XCTAssertTrue(containsLatexMarkdown("可写成 \\(x^2 + y^2 = z^2\\)"))
        XCTAssertTrue(containsLatexMarkdown("\\[\\int_0^1 x^2 dx = \\frac{1}{3}\\]"))
    }

    func testReturnsFalseForPlainMarkdown() {
        XCTAssertFalse(containsLatexMarkdown("**结论**：先列已知，再列目标。"))
    }

    func testIgnoresEscapedCurrencyText() {
        XCTAssertFalse(containsLatexMarkdown("价格是 \\$100，不是公式"))
    }

    func testNormalizeConvertsSingleDollarInlineFormula() {
        let normalized = normalizeLatexForMarkwon("抛物线顶点可以写成 $y=a(x-h)^2+k$ 的形式")
        XCTAssertTrue(normalized.contains("$$y=a(x-h)^2+k$$"))
    }

    func testNormalizeConvertsSlashParenAndSlashBracketForms() {
        let normalized = normalizeLatexForMarkwon("可写成 \\(x^2 + y^2 = z^2\\)，也可写成 \\[x^2+y^2=z^2\\]")
        XCTAssertTrue(normalized.contains("$$x^2 + y^2 = z^2$$"))
        XCTAssertTrue(normalized.contains("$$\nx^2+y^2=z^2\n$$"))
    }

    func testNormalizeKeepsOrderedListTextAroundInlineFormula() {
        let normalized = normalizeLatexForMarkwon("1. 由核反应前后**质量数守恒**：\\(235+1=236\\)，而\\(141+92=233\\)，所以 \\(3X\\) 的总质量数是 3。")
        XCTAssertTrue(normalized.hasPrefix("1. "))
        XCTAssertTrue(normalized.contains("$$235+1=236$$"))
        XCTAssertTrue(normalized.contains("$$141+92=233$$"))
        XCTAssertTrue(normalized.contains("$$3X$$"))
    }

    func testNormalizePreservesIndentedBlockFormulaInsideOrderedList() {
        let markdown = """
        2. 双缝干涉公式：
           \\[
           \\Delta x=\\frac{L\\lambda}{d}
           \\]
        3. 代入数据。
        """
        let normalized = normalizeLatexForMarkwon(markdown)
        XCTAssertTrue(normalized.contains("2. 双缝干涉公式："))
        XCTAssertTrue(normalized.contains("\n   $$\n   \\Delta x=\\frac{L\\lambda}{d}\n   $$\n3. 代入数据。"))
    }

    func testNormalizeKeepsEscapedCurrencyTextUnchanged() {
        let markdown = "价格是 \\$100，不是公式"
        XCTAssertEqual(markdown, normalizeLatexForMarkwon(markdown))
    }
}

//
//  Created by Mike Griebling on 2022-12-31.
//  Translated from an Objective-C implementation by Kostub Deshmukh.
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

import CoreText
import Foundation
import QuartzCore
import SwiftUI

func isIos6Supported() -> Bool {
	if !MTDisplay.initialized {
		#if os(iOS) || os(visionOS)
			let reqSysVer = "6.0"
			let currSysVer = UIDevice.current.systemVersion
			if currSysVer.compare(reqSysVer, options: .numeric) != .orderedAscending {
				MTDisplay.supported = true
			}
		#else
			MTDisplay.supported = true
		#endif
		MTDisplay.initialized = true
	}
	return MTDisplay.supported
}

/// The Downshift protocol allows an MTDisplay to be shifted down by a given amount.
protocol DownShift {
	var shiftDown: CGFloat { set get }
}

// MARK: - MTDisplay

/// The base class for rendering a math equation.
public class MTDisplay: NSObject {
	// needed for isIos6Supported() func above
	static var initialized = false
	static var supported = false

	/// Draws itself in the given graphics context.
	public func draw(_ context: CGContext) {
		if localBackgroundColor != nil {
			context.saveGState()
			context.setBlendMode(.normal)
			context.setFillColor(localBackgroundColor!.cgColor)
			context.fill(displayBounds())
			context.restoreGState()
		}
	}

	/// Gets the bounding rectangle for the MTDisplay
	func displayBounds() -> CGRect {
		CGRectMake(position.x, position.y - descent, width, ascent + descent)
	}

	// For debugging. Shows the object in quick look in Xcode.
	#if os(iOS) || os(visionOS)
		func debugQuickLookObject() -> Any {
			let size = CGSizeMake(width, ascent + descent)
			UIGraphicsBeginImageContext(size)

			// get a reference to that context we created
			let context = UIGraphicsGetCurrentContext()!
			// translate/flip the graphics context (for transforming from CG* coords to UI* coords
			context.translateBy(x: 0, y: size.height)
			context.scaleBy(x: 1.0, y: -1.0)
			// move the position to (0,0)
			context.translateBy(x: -position.x, y: -position.y)

			// Move the line up by self.descent
			context.translateBy(x: 0, y: descent)
			// Draw self on context
			draw(context)

			// generate a new UIImage from the graphics context we drew onto
			let img = UIGraphicsGetImageFromCurrentImageContext()
			return img as Any
		}
	#endif

	/// The distance from the axis to the top of the display
	public var ascent: CGFloat = 0
	/// The distance from the axis to the bottom of the display
	public var descent: CGFloat = 0
	/// The width of the display
	public var width: CGFloat = 0
	/// Position of the display with respect to the parent view or display.
	var position = CGPoint.zero
	/// The range of characters supported by this item
	public var range: NSRange = NSMakeRange(0, 0)
	/// Whether the display has a subscript/superscript following it.
	public var hasScript: Bool = false
	/// The text color for this display
	var textColor: MTColor?
	/// The local color, if the color was mutated local with the color command
	var localTextColor: MTColor?
	/// The background color for this display
	var localBackgroundColor: MTColor?
}

/// Special class to be inherited from that implements the DownShift protocol
class MTDisplayDS: MTDisplay, DownShift {
	var shiftDown: CGFloat = 0
}

// MARK: - MTCTLineDisplay

/// A rendering of a single CTLine as an MTDisplay
public class MTCTLineDisplay: MTDisplay {
	/// The CTLine being displayed
	public var line: CTLine!
	/// The attributed string used to generate the CTLineRef. Note setting this does not reset the dimensions of
	/// the display. So set only when
	var attributedString: NSAttributedString? {
		didSet {
			line = CTLineCreateWithAttributedString(attributedString!)
		}
	}

	/// An array of MTMathAtoms that this CTLine displays. Used for indexing back into the MTMathList
	public fileprivate(set) var atoms = [MTMathAtom]()

	init(withString attrString: NSAttributedString?, position: CGPoint, range: NSRange, font: MTFont?, atoms: [MTMathAtom]) {
		super.init()
		self.position = position
		attributedString = attrString
		line = CTLineCreateWithAttributedString(attrString!)
		self.range = range
		self.atoms = atoms
		// We can't use typographic bounds here as the ascent and descent returned are for the font and not for the line.
		width = CTLineGetTypographicBounds(line, nil, nil, nil)
		if isIos6Supported() {
			let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
			ascent = max(0, CGRectGetMaxY(bounds) - 0)
			descent = max(0, 0 - CGRectGetMinY(bounds))
			// TODO: Should we use this width vs the typographic width? They are slightly different. Don't know why.
			// _width = CGRectGetMaxX(bounds);
		} else {
			// Our own implementation of the ios6 function to get glyph path bounds.
			computeDimensions(font)
		}
	}

	override var textColor: MTColor? {
		set {
			super.textColor = newValue
			let attrStr = attributedString!.mutableCopy() as! NSMutableAttributedString
			let foregroundColor = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
			attrStr.addAttribute(foregroundColor, value: self.textColor!.cgColor, range: NSMakeRange(0, attrStr.length))
			attributedString = attrStr
		}
		get { super.textColor }
	}

	func computeDimensions(_ font: MTFont?) {
		let runs = CTLineGetGlyphRuns(line) as NSArray
		for obj in runs {
			let run = obj as! CTRun?
			let numGlyphs = CTRunGetGlyphCount(run!)
			var glyphs = [CGGlyph]()
			glyphs.reserveCapacity(numGlyphs)
			CTRunGetGlyphs(run!, CFRangeMake(0, numGlyphs), &glyphs)
			let bounds = CTFontGetBoundingRectsForGlyphs(font!.ctFont, .horizontal, glyphs, nil, numGlyphs)
			let ascent = max(0, CGRectGetMaxY(bounds) - 0)
			// Descent is how much the line goes below the origin. However if the line is all above the origin, then descent can't be negative.
			let descent = max(0, 0 - CGRectGetMinY(bounds))
			if ascent > self.ascent {
				self.ascent = ascent
			}
			if descent > self.descent {
				self.descent = descent
			}
		}
	}

	override public func draw(_ context: CGContext) {
		super.draw(context)
		context.saveGState()

		context.textPosition = position
		CTLineDraw(line, context)

		context.restoreGState()
	}
}

// MARK: - MTMathListDisplay

/// An MTLine is a rendered form of MTMathList in one line.
/// It can render itself using the draw method.
public class MTMathListDisplay: MTDisplay {
	/**
	      The type of position for a line, i.e. subscript/superscript or regular.
	 */
	public enum LinePosition: Int {
		/// Regular
		case regular
		/// Positioned at a subscript
		case ssubscript
		/// Positioned at a superscript
		case superscript
	}

	/// Where the line is positioned
	public var type: LinePosition = .regular
	/// An array of MTDisplays which are positioned relative to the position of the
	/// the current display.
	public fileprivate(set) var subDisplays = [MTDisplay]()
	/// If a subscript or superscript this denotes the location in the parent MTList. For a
	/// regular list this is NSNotFound
	public var index: Int = 0

	init(withDisplays displays: [MTDisplay], range: NSRange) {
		super.init()
		subDisplays = displays
		position = CGPoint.zero
		type = .regular
		index = NSNotFound
		self.range = range
		recomputeDimensions()
	}

	override var textColor: MTColor? {
		set {
			super.textColor = newValue
			for displayAtom in subDisplays {
				if displayAtom.localTextColor == nil {
					displayAtom.textColor = newValue
				} else {
					displayAtom.textColor = displayAtom.localTextColor
				}
			}
		}
		get { super.textColor }
	}

	override public func draw(_ context: CGContext) {
		super.draw(context)
		context.saveGState()

		// Make the current position the origin as all the positions of the sub atoms are relative to the origin.
		context.translateBy(x: position.x, y: position.y)
		context.textPosition = CGPoint.zero

		// draw each atom separately
		for displayAtom in subDisplays {
			displayAtom.draw(context)
		}

		context.restoreGState()
	}

	func recomputeDimensions() {
		var max_ascent: CGFloat = 0
		var max_descent: CGFloat = 0
		var max_width: CGFloat = 0
		for atom in subDisplays {
			let ascent = max(0, atom.position.y + atom.ascent)
			if ascent > max_ascent {
				max_ascent = ascent
			}

			let descent = max(0, 0 - (atom.position.y - atom.descent))
			if descent > max_descent {
				max_descent = descent
			}
			let width = atom.width + atom.position.x
			if width > max_width {
				max_width = width
			}
		}
		ascent = max_ascent
		descent = max_descent
		width = max_width
	}
}

// MARK: - MTFractionDisplay

/// Rendering of an MTFraction as an MTDisplay
public class MTFractionDisplay: MTDisplay {
	/** A display representing the numerator of the fraction. Its position is relative
	 to the parent and is not treated as a sub-display.
	 */
	public fileprivate(set) var numerator: MTMathListDisplay?
	/** A display representing the denominator of the fraction. Its position is relative
	 to the parent is not treated as a sub-display.
	 */
	public fileprivate(set) var denominator: MTMathListDisplay?

	var numeratorUp: CGFloat = 0 {
		didSet { updateNumeratorPosition() }
	}

	var denominatorDown: CGFloat = 0 {
		didSet { updateDenominatorPosition() }
	}

	var linePosition: CGFloat = 0
	var lineThickness: CGFloat = 0

	init(withNumerator numerator: MTMathListDisplay?, denominator: MTMathListDisplay?, position: CGPoint, range: NSRange) {
		super.init()
		self.numerator = numerator
		self.denominator = denominator
		self.position = position
		self.range = range
		assert(self.range.length == 1, "Fraction range length not 1 - range (\(range.location), \(range.length)")
	}

	override public var ascent: CGFloat {
		set { super.ascent = newValue }
		get { numerator!.ascent + numeratorUp }
	}

	override public var descent: CGFloat {
		set { super.descent = newValue }
		get { denominator!.descent + denominatorDown }
	}

	override public var width: CGFloat {
		set { super.width = newValue }
		get { max(numerator!.width, denominator!.width) }
	}

	func updateDenominatorPosition() {
		guard denominator != nil else { return }
		denominator!.position = CGPointMake(position.x + (width - denominator!.width) / 2, position.y - denominatorDown)
	}

	func updateNumeratorPosition() {
		guard numerator != nil else { return }
		numerator!.position = CGPointMake(position.x + (width - numerator!.width) / 2, position.y + numeratorUp)
	}

	override var position: CGPoint {
		set {
			super.position = newValue
			updateDenominatorPosition()
			updateNumeratorPosition()
		}
		get { super.position }
	}

	override var textColor: MTColor? {
		set {
			super.textColor = newValue
			numerator?.textColor = newValue
			denominator?.textColor = newValue
		}
		get { super.textColor }
	}

	override public func draw(_ context: CGContext) {
		super.draw(context)
		numerator?.draw(context)
		denominator?.draw(context)

		context.saveGState()

		textColor?.setStroke()

		// draw the horizontal line
		// Note: line thickness of 0 draws the thinnest possible line - we want no line so check for 0s
		if lineThickness > 0 {
			let path = MTBezierPath()
			path.move(to: CGPointMake(position.x, position.y + linePosition))
			path.addLine(to: CGPointMake(position.x + width, position.y + linePosition))
			path.lineWidth = lineThickness
			path.stroke()
		}

		context.restoreGState()
	}
}

// MARK: - MTRadicalDisplay

/// Rendering of an MTRadical as an MTDisplay
class MTRadicalDisplay: MTDisplay {
	/** A display representing the radicand of the radical. Its position is relative
	 to the parent is not treated as a sub-display.
	 */
	fileprivate(set) var radicand: MTMathListDisplay?
	/** A display representing the degree of the radical. Its position is relative
	 to the parent is not treated as a sub-display.
	 */
	fileprivate(set) var degree: MTMathListDisplay?

	override var position: CGPoint {
		set {
			super.position = newValue
			updateRadicandPosition()
		}
		get { super.position }
	}

	override var textColor: MTColor? {
		set {
			super.textColor = newValue
			radicand?.textColor = newValue
			degree?.textColor = newValue
		}
		get { super.textColor }
	}

	private var _radicalGlyph: MTDisplay?
	private var _radicalShift: CGFloat = 0

	var topKern: CGFloat = 0
	var lineThickness: CGFloat = 0

	init(withRadicand radicand: MTMathListDisplay?, glyph: MTDisplay, position: CGPoint, range: NSRange) {
		super.init()
		self.radicand = radicand
		_radicalGlyph = glyph
		_radicalShift = 0

		self.position = position
		self.range = range
	}

	func setDegree(_ degree: MTMathListDisplay?, fontMetrics: MTFontMathTable?) {
		// sets up the degree of the radical
		var kernBefore = fontMetrics!.radicalKernBeforeDegree
		let kernAfter = fontMetrics!.radicalKernAfterDegree
		let raise = fontMetrics!.radicalDegreeBottomRaisePercent * (ascent - descent)

		// The layout is:
		// kernBefore, raise, degree, kernAfter, radical
		self.degree = degree

		// the radical is now shifted by kernBefore + degree.width + kernAfter
		_radicalShift = kernBefore + degree!.width + kernAfter
		if _radicalShift < 0 {
			// we can't have the radical shift backwards, so instead we increase the kernBefore such
			// that _radicalShift will be 0.
			kernBefore -= _radicalShift
			_radicalShift = 0
		}

		// Note: position of degree is relative to parent.
		self.degree!.position = CGPointMake(position.x + kernBefore, position.y + raise)
		// Update the width by the _radicalShift
		width = _radicalShift + _radicalGlyph!.width + radicand!.width
		// update the position of the radicand
		updateRadicandPosition()
	}

	func updateRadicandPosition() {
		// The position of the radicand includes the position of the MTRadicalDisplay
		// This is to make the positioning of the radical consistent with fractions and
		// have the cursor position finding algorithm work correctly.
		// move the radicand by the width of the radical sign
		radicand!.position = CGPointMake(position.x + _radicalShift + _radicalGlyph!.width, position.y)
	}

	override func draw(_ context: CGContext) {
		super.draw(context)

		// draw the radicand & degree at its position
		radicand?.draw(context)
		degree?.draw(context)

		context.saveGState()
		textColor?.setStroke()
		textColor?.setFill()

		// Make the current position the origin as all the positions of the sub atoms are relative to the origin.
		context.translateBy(x: position.x + _radicalShift, y: position.y)
		context.textPosition = CGPoint.zero

		// Draw the glyph.
		_radicalGlyph?.draw(context)

		// Draw the VBOX
		// for the kern of, we don't need to draw anything.
		let heightFromTop = topKern

		// draw the horizontal line with the given thickness
		let path = MTBezierPath()
		let lineStart = CGPointMake(_radicalGlyph!.width, ascent - heightFromTop - lineThickness / 2) // subtract half the line thickness to center the line
		let lineEnd = CGPointMake(lineStart.x + radicand!.width, lineStart.y)
		path.move(to: lineStart)
		path.addLine(to: lineEnd)
		path.lineWidth = lineThickness
		path.lineCapStyle = .round
		path.stroke()

		context.restoreGState()
	}
}

// MARK: - MTGlyphDisplay

/// Rendering a glyph as a display
class MTGlyphDisplay: MTDisplayDS {
	var glyph: CGGlyph!
	var font: MTFont?

	init(withGlpyh glyph: CGGlyph, range: NSRange, font: MTFont?) {
		super.init()
		self.font = font
		self.glyph = glyph

		position = CGPoint.zero
		self.range = range
	}

	override func draw(_ context: CGContext) {
		super.draw(context)
		context.saveGState()

		textColor?.setFill()

		// Make the current position the origin as all the positions of the sub atoms are relative to the origin.

		context.translateBy(x: position.x, y: position.y - shiftDown)
		context.textPosition = CGPoint.zero

		var pos = CGPoint.zero
		CTFontDrawGlyphs(font!.ctFont, &glyph, &pos, 1, context)

		context.restoreGState()
	}

	override var ascent: CGFloat {
		set { super.ascent = newValue }
		get { super.ascent - shiftDown }
	}

	override var descent: CGFloat {
		set { super.descent = newValue }
		get { super.descent + shiftDown }
	}
}

// MARK: - MTGlyphConstructionDisplay

class MTGlyphConstructionDisplay: MTDisplayDS {
	var glyphs = [CGGlyph]()
	var positions = [CGPoint]()
	var font: MTFont?
	var numGlyphs: Int = 0

	init(withGlyphs glyphs: [NSNumber?], offsets: [NSNumber?], font: MTFont?) {
		super.init()
		assert(glyphs.count == offsets.count, "Glyphs and offsets need to match")
		numGlyphs = glyphs.count
		self.glyphs = [CGGlyph](repeating: CGGlyph(), count: numGlyphs) // malloc(sizeof(CGGlyph) * _numGlyphs);
		positions = [CGPoint](repeating: CGPoint.zero, count: numGlyphs) // malloc(sizeof(CGPoint) * _numGlyphs);
		for i in 0 ..< numGlyphs {
			self.glyphs[i] = glyphs[i]!.uint16Value
			positions[i] = CGPointMake(0, CGFloat(offsets[i]!.floatValue))
		}
		self.font = font
		position = CGPoint.zero
	}

	override func draw(_ context: CGContext) {
		super.draw(context)
		context.saveGState()

		textColor?.setFill()

		// Make the current position the origin as all the positions of the sub atoms are relative to the origin.
		context.translateBy(x: position.x, y: position.y - shiftDown)
		context.textPosition = CGPoint.zero

		// Draw the glyphs.
		CTFontDrawGlyphs(font!.ctFont, glyphs, positions, numGlyphs, context)

		context.restoreGState()
	}

	override var ascent: CGFloat {
		set { super.ascent = newValue }
		get { super.ascent - shiftDown }
	}

	override var descent: CGFloat {
		set { super.descent = newValue }
		get { super.descent + shiftDown }
	}
}

// MARK: - MTLargeOpLimitsDisplay

/// Rendering a large operator with limits as an MTDisplay
class MTLargeOpLimitsDisplay: MTDisplay {
	/** A display representing the upper limit of the large operator. Its position is relative
	 to the parent is not treated as a sub-display.
	 */
	var upperLimit: MTMathListDisplay?
	/** A display representing the lower limit of the large operator. Its position is relative
	 to the parent is not treated as a sub-display.
	 */
	var lowerLimit: MTMathListDisplay?

	var limitShift: CGFloat = 0
	var upperLimitGap: CGFloat = 0 {
		didSet { updateUpperLimitPosition() }
	}

	var lowerLimitGap: CGFloat = 0 {
		didSet { updateLowerLimitPosition() }
	}

	var extraPadding: CGFloat = 0

	var nucleus: MTDisplay?

	init(withNucleus nucleus: MTDisplay?, upperLimit: MTMathListDisplay?, lowerLimit: MTMathListDisplay?, limitShift: CGFloat, extraPadding: CGFloat) {
		super.init()
		self.upperLimit = upperLimit
		self.lowerLimit = lowerLimit
		self.nucleus = nucleus

		var maxWidth = max(nucleus!.width, upperLimit?.width ?? 0)
		maxWidth = max(maxWidth, lowerLimit?.width ?? 0)

		self.limitShift = limitShift
		upperLimitGap = 0
		lowerLimitGap = 0
		self.extraPadding = extraPadding // corresponds to \xi_13 in TeX
		width = maxWidth
	}

	override var ascent: CGFloat {
		set { super.ascent = newValue }
		get {
			if upperLimit != nil {
				nucleus!.ascent + extraPadding + upperLimit!.ascent + upperLimitGap + upperLimit!.descent
			} else {
				nucleus!.ascent
			}
		}
	}

	override var descent: CGFloat {
		set { super.descent = newValue }
		get {
			if lowerLimit != nil {
				nucleus!.descent + extraPadding + lowerLimitGap + lowerLimit!.descent + lowerLimit!.ascent
			} else {
				nucleus!.descent
			}
		}
	}

	override var position: CGPoint {
		set {
			super.position = newValue
			updateLowerLimitPosition()
			updateUpperLimitPosition()
			updateNucleusPosition()
		}
		get { super.position }
	}

	func updateLowerLimitPosition() {
		if lowerLimit != nil {
			// The position of the lower limit includes the position of the MTLargeOpLimitsDisplay
			// This is to make the positioning of the radical consistent with fractions and radicals
			// Move the starting point to below the nucleus leaving a gap of _lowerLimitGap and subtract
			// the ascent to to get the baseline. Also center and shift it to the left by _limitShift.
			lowerLimit!.position = CGPointMake(position.x - limitShift + (width - lowerLimit!.width) / 2,
			                                   position.y - nucleus!.descent - lowerLimitGap - lowerLimit!.ascent)
		}
	}

	func updateUpperLimitPosition() {
		if upperLimit != nil {
			// The position of the upper limit includes the position of the MTLargeOpLimitsDisplay
			// This is to make the positioning of the radical consistent with fractions and radicals
			// Move the starting point to above the nucleus leaving a gap of _upperLimitGap and add
			// the descent to to get the baseline. Also center and shift it to the right by _limitShift.
			upperLimit!.position = CGPointMake(position.x + limitShift + (width - upperLimit!.width) / 2,
			                                   position.y + nucleus!.ascent + upperLimitGap + upperLimit!.descent)
		}
	}

	func updateNucleusPosition() {
		// Center the nucleus
		nucleus?.position = CGPointMake(position.x + (width - nucleus!.width) / 2, position.y)
	}

	override var textColor: MTColor? {
		set {
			super.textColor = newValue
			upperLimit?.textColor = newValue
			lowerLimit?.textColor = newValue
			nucleus?.textColor = newValue
		}
		get { super.textColor }
	}

	override func draw(_ context: CGContext) {
		super.draw(context)
		// Draw the elements.
		upperLimit?.draw(context)
		lowerLimit?.draw(context)
		nucleus?.draw(context)
	}
}

// MARK: - MTLineDisplay

/// Rendering of an list with an overline or underline
class MTLineDisplay: MTDisplay {
	/** A display representing the inner list that is underlined. Its position is relative
	 to the parent is not treated as a sub-display.
	 */
	var inner: MTMathListDisplay?
	var lineShiftUp: CGFloat = 0
	var lineThickness: CGFloat = 0

	init(withInner inner: MTMathListDisplay?, position: CGPoint, range: NSRange) {
		super.init()
		self.inner = inner

		self.position = position
		self.range = range
	}

	override var textColor: MTColor? {
		set {
			super.textColor = newValue
			inner?.textColor = newValue
		}
		get { super.textColor }
	}

	override var position: CGPoint {
		set {
			super.position = newValue
			updateInnerPosition()
		}
		get { super.position }
	}

	override func draw(_ context: CGContext) {
		super.draw(context)
		inner?.draw(context)

		context.saveGState()

		textColor?.setStroke()

		// draw the horizontal line
		let path = MTBezierPath()
		let lineStart = CGPointMake(position.x, position.y + lineShiftUp)
		let lineEnd = CGPointMake(lineStart.x + inner!.width, lineStart.y)
		path.move(to: lineStart)
		path.addLine(to: lineEnd)
		path.lineWidth = lineThickness
		path.stroke()

		context.restoreGState()
	}

	func updateInnerPosition() {
		inner?.position = CGPointMake(position.x, position.y)
	}
}

// MARK: - MTAccentDisplay

/// Rendering an accent as a display
class MTAccentDisplay: MTDisplay {
	/** A display representing the inner list that is accented. Its position is relative
	 to the parent is not treated as a sub-display.
	 */
	var accentee: MTMathListDisplay?

	/** A display representing the accent. Its position is relative to the current display.
	 */
	var accent: MTGlyphDisplay?

	init(withAccent glyph: MTGlyphDisplay?, accentee: MTMathListDisplay?, range: NSRange) {
		super.init()
		accent = glyph
		self.accentee = accentee
		self.accentee?.position = CGPoint.zero
		self.range = range
	}

	override var textColor: MTColor? {
		set {
			super.textColor = newValue
			accentee?.textColor = newValue
			accent?.textColor = newValue
		}
		get { super.textColor }
	}

	override var position: CGPoint {
		set {
			super.position = newValue
			updateAccenteePosition()
		}
		get { super.position }
	}

	func updateAccenteePosition() {
		accentee?.position = CGPointMake(position.x, position.y)
	}

	override func draw(_ context: CGContext) {
		super.draw(context)
		accentee?.draw(context)

		context.saveGState()
		context.translateBy(x: position.x, y: position.y)
		context.textPosition = CGPoint.zero

		accent?.draw(context)

		context.restoreGState()
	}
}

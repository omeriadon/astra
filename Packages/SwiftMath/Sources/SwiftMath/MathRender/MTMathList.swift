//
//  Created by Mike Griebling on 2022-12-31.
//  Translated from an Objective-C implementation by Kostub Deshmukh.
//
//  This software may be modified and distributed under the terms of the
//  MIT license. See the LICENSE file for details.
//

import Foundation

/**
 The type of atom in a `MTMathList`.

 The type of the atom determines how it is rendered, and spacing between the atoms.
 */
public enum MTMathAtomType: Int, CustomStringConvertible, Comparable {
	/// A number or text in ordinary format - Ord in TeX
	case ordinary = 1
	/// A number - Does not exist in TeX
	case number
	/// A variable (i.e. text in italic format) - Does not exist in TeX
	case variable
	/// A large operator such as (sin/cos, integral etc.) - Op in TeX
	case largeOperator
	/// A binary operator - Bin in TeX
	case binaryOperator
	/// A unary operator - Does not exist in TeX.
	case unaryOperator
	/// A relation, e.g. = > < etc. - Rel in TeX
	case relation
	/// Open brackets - Open in TeX
	case open
	/// Close brackets - Close in TeX
	case close
	/// A fraction e.g 1/2 - generalized fraction node in TeX
	case fraction
	/// A radical operator e.g. sqrt(2)
	case radical
	/// Punctuation such as , - Punct in TeX
	case punctuation
	/// A placeholder square for future input. Does not exist in TeX
	case placeholder
	/// An inner atom, i.e. an embedded math list - Inner in TeX
	case inner
	/// An underlined atom - Under in TeX
	case underline
	/// An overlined atom - Over in TeX
	case overline
	/// An accented atom - Accent in TeX
	case accent

	// Atoms after this point do not support subscripts or superscripts

	/// A left atom - Left & Right in TeX. We don't need two since we track boundaries separately.
	case boundary = 101

	// Atoms after this are non-math TeX nodes that are still useful in math mode. They do not have
	// the usual structure.

	/// Spacing between math atoms. This denotes both glue and kern for TeX. We do not
	/// distinguish between glue and kern.
	case space = 201

	/// Denotes style changes during rendering.
	case style
	case color
	case textcolor
	case colorBox

	// Atoms after this point are not part of TeX and do not have the usual structure.

	/// An table atom. This atom does not exist in TeX. It is equivalent to the TeX command
	/// halign which is handled outside of the TeX math rendering engine. We bring it into our
	/// math typesetting to handle matrices and other tables.
	case table = 1001

	func isNotBinaryOperator() -> Bool {
		switch self {
			case .binaryOperator, .relation, .open, .punctuation, .largeOperator: true
			default: false
		}
	}

	func isScriptAllowed() -> Bool {
		self < .boundary
	}

	/// we want string representations to be capitalized
	public var description: String {
		switch self {
			case .ordinary: "Ordinary"
			case .number: "Number"
			case .variable: "Variable"
			case .largeOperator: "Large Operator"
			case .binaryOperator: "Binary Operator"
			case .unaryOperator: "Unary Operator"
			case .relation: "Relation"
			case .open: "Open"
			case .close: "Close"
			case .fraction: "Fraction"
			case .radical: "Radical"
			case .punctuation: "Punctuation"
			case .placeholder: "Placeholder"
			case .inner: "Inner"
			case .underline: "Underline"
			case .overline: "Overline"
			case .accent: "Accent"
			case .boundary: "Boundary"
			case .space: "Space"
			case .style: "Style"
			case .color: "Color"
			case .textcolor: "TextColor"
			case .colorBox: "Colorbox"
			case .table: "Table"
		}
	}

	/// comparable support
	public static func < (lhs: MTMathAtomType, rhs: MTMathAtomType) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

/**
 The font style of a character.

 The fontstyle of the atom determines what style the character is rendered in. This only applies to atoms
 of type kMTMathAtomVariable and kMTMathAtomNumber. None of the other atom types change their font style.
 */
public enum MTFontStyle: Int {
	/// The default latex rendering style. i.e. variables are italic and numbers are roman.
	case defaultStyle = 0,
	     // Roman font style i.e. \mathrm
	     roman,
	     // Bold font style i.e. \mathbf
	     bold,
	     // Caligraphic font style i.e. \mathcal
	     caligraphic,
	     // Typewriter (monospace) style i.e. \mathtt
	     typewriter,
	     // Italic style i.e. \mathit
	     italic,
	     // San-serif font i.e. \mathss
	     sansSerif,
	     // Fractur font i.e \mathfrak
	     fraktur,
	     // Blackboard font i.e. \mathbb
	     blackboard,
	     // Bold italic
	     boldItalic
}

// MARK: - MTMathAtom

/** A `MTMathAtom` is the basic unit of a math list. Each atom represents a single character
 or mathematical operator in a list. However certain atoms can represent more complex structures
 such as fractions and radicals. Each atom has a type which determines how the atom is rendered and
 a nucleus. The nucleus contains the character(s) that need to be rendered. However the nucleus may
 be empty for certain types of atoms. An atom has an optional subscript or superscript which represents
 the subscript or superscript that is to be rendered.

 Certain types of atoms inherit from `MTMathAtom` and may have additional fields.
 */
public class MTMathAtom: NSObject {
	/** The type of the atom. */
	public var type = MTMathAtomType.ordinary
	/** An optional subscript. */
	public var subScript: MTMathList? {
		didSet {
			if subScript != nil, !isScriptAllowed() {
				subScript = nil
				NSException(name: NSExceptionName(rawValue: "Error"), reason: "Subscripts not allowed for atom of type \(type)").raise()
			}
		}
	}

	/** An optional superscript. */
	public var superScript: MTMathList? {
		didSet {
			if superScript != nil, !isScriptAllowed() {
				superScript = nil
				NSException(name: NSExceptionName(rawValue: "Error"), reason: "Superscripts not allowed for atom of type \(type)").raise()
			}
		}
	}

	/** The nucleus of the atom. */
	public var nucleus: String = ""

	/// The index range in the MTMathList this MTMathAtom tracks. This is used by the finalizing and preprocessing steps
	/// which fuse MTMathAtoms to track the position of the current MTMathAtom in the original list.
	public var indexRange = NSRange(location: 0, length: 0) // indexRange in list that this atom tracks:

	/** The font style to be used for the atom. */
	var fontStyle: MTFontStyle = .defaultStyle

	/// If this atom was formed by fusion of multiple atoms, then this stores the list of atoms that were fused to create this one.
	/// This is used in the finalizing and preprocessing steps.
	var fusedAtoms = [MTMathAtom]()

	init(_ atom: MTMathAtom?) {
		guard let atom else { return }
		type = atom.type
		nucleus = atom.nucleus
		subScript = MTMathList(atom.subScript)
		superScript = MTMathList(atom.superScript)
		indexRange = atom.indexRange
		fontStyle = atom.fontStyle
		fusedAtoms = atom.fusedAtoms
	}

	override init() {}

	/// Factory function to create an atom with a given type and value.
	/// - parameter type: The type of the atom to instantiate.
	/// - parameter value: The value of the atoms nucleus. The value is ignored for fractions and radicals.
	init(type: MTMathAtomType, value: String) {
		self.type = type
		nucleus = type == .radical ? "" : value
	}

	/// Returns a copy of `self`.
	public func copy() -> MTMathAtom {
		switch type {
			case .largeOperator:
				MTLargeOperator(self as? MTLargeOperator)
			case .fraction:
				MTFraction(self as? MTFraction)
			case .radical:
				MTRadical(self as? MTRadical)
			case .style:
				MTMathStyle(self as? MTMathStyle)
			case .inner:
				MTInner(self as? MTInner)
			case .underline:
				MTUnderLine(self as? MTUnderLine)
			case .overline:
				MTOverLine(self as? MTOverLine)
			case .accent:
				MTAccent(self as? MTAccent)
			case .space:
				MTMathSpace(self as? MTMathSpace)
			case .color:
				MTMathColor(self as? MTMathColor)
			case .textcolor:
				MTMathTextColor(self as? MTMathTextColor)
			case .colorBox:
				MTMathColorbox(self as? MTMathColorbox)
			case .table:
				MTMathTable(self as! MTMathTable)
			default:
				MTMathAtom(self)
		}
	}

	override public var description: String {
		var string = ""
		string += nucleus
		if superScript != nil {
			string += "^{\(superScript!.description)}"
		}
		if subScript != nil {
			string += "_{\(subScript!.description)}"
		}
		return string
	}

	/// Returns a finalized copy of the atom
	public var finalized: MTMathAtom {
		let finalized: MTMathAtom = copy()
		finalized.superScript = finalized.superScript?.finalized
		finalized.subScript = finalized.subScript?.finalized
		return finalized
	}

	public var string: String {
		var str = nucleus
		if let superScript {
			str.append("^{\(superScript.string)}")
		}
		if let subScript {
			str.append("_{\(subScript.string)}")
		}
		return str
	}

	/// Fuse the given atom with this one by combining their nucleii.
	func fuse(with atom: MTMathAtom) {
		assert(subScript == nil, "Cannot fuse into an atom which has a subscript: \(self)")
		assert(superScript == nil, "Cannot fuse into an atom which has a superscript: \(self)")
		assert(atom.type == type, "Only atoms of the same type can be fused. \(self), \(atom)")
		guard subScript == nil, superScript == nil, type == atom.type
		else { print("Can't fuse these 2 atoms"); return }

		// Update the fused atoms list
		if fusedAtoms.isEmpty {
			fusedAtoms.append(MTMathAtom(self))
		}
		if atom.fusedAtoms.count > 0 {
			fusedAtoms.append(contentsOf: atom.fusedAtoms)
		} else {
			fusedAtoms.append(atom)
		}

		// Update nucleus:
		nucleus += atom.nucleus

		// Update range:
		indexRange.length += atom.indexRange.length

		// Update super/subscript:
		superScript = atom.superScript
		subScript = atom.subScript
	}

	/** Returns true if this atom allows scripts (sub or super). */
	func isScriptAllowed() -> Bool {
		type.isScriptAllowed()
	}

	func isNotBinaryOperator() -> Bool {
		type.isNotBinaryOperator()
	}
}

func isNotBinaryOperator(_ prevNode: MTMathAtom?) -> Bool {
	guard let prevNode else { return true }
	return prevNode.type.isNotBinaryOperator()
}

// MARK: - MTFraction

public class MTFraction: MTMathAtom {
	public var hasRule: Bool = true
	public var leftDelimiter = ""
	public var rightDelimiter = ""
	public var numerator: MTMathList?
	public var denominator: MTMathList?

	init(_ frac: MTFraction?) {
		super.init(frac)
		type = .fraction
		if let frac {
			numerator = MTMathList(frac.numerator)
			denominator = MTMathList(frac.denominator)
			hasRule = frac.hasRule
			leftDelimiter = frac.leftDelimiter
			rightDelimiter = frac.rightDelimiter
		}
	}

	init(hasRule rule: Bool = true) {
		super.init()
		type = .fraction
		hasRule = rule
	}

	override public var description: String {
		var string = hasRule ? "\\frac" : "\\atop"
		if !leftDelimiter.isEmpty {
			string += "[\(leftDelimiter)]"
		}
		if !rightDelimiter.isEmpty {
			string += "[\(rightDelimiter)]"
		}
		string += "{\(numerator?.description ?? "placeholder")}{\(denominator?.description ?? "placeholder")}"
		if superScript != nil {
			string += "^{\(superScript!.description)}"
		}
		if subScript != nil {
			string += "_{\(subScript!.description)}"
		}
		return string
	}

	override public var finalized: MTMathAtom {
		let newFrac = super.finalized as! MTFraction
		newFrac.numerator = newFrac.numerator?.finalized
		newFrac.denominator = newFrac.denominator?.finalized
		return newFrac
	}
}

// MARK: - MTRadical

/** An atom of type radical (square root). */
public class MTRadical: MTMathAtom {
	/// Denotes the term under the square root sign
	public var radicand: MTMathList?

	/// Denotes the degree of the radical, i.e. the value to the top left of the radical sign
	/// This can be null if there is no degree.
	public var degree: MTMathList?

	init(_ rad: MTRadical?) {
		super.init(rad)
		type = .radical
		radicand = MTMathList(rad?.radicand)
		degree = MTMathList(rad?.degree)
		nucleus = ""
	}

	override init() {
		super.init()
		type = .radical
		nucleus = ""
	}

	override public var description: String {
		var string = "\\sqrt"
		if degree != nil {
			string += "[\(degree!.description)]"
		}
		if radicand != nil {
			string += "{\(radicand?.description ?? "placeholder")}"
		}
		if superScript != nil {
			string += "^{\(superScript!.description)}"
		}
		if subScript != nil {
			string += "_{\(subScript!.description)}"
		}
		return string
	}

	override public var finalized: MTMathAtom {
		let newRad = super.finalized as! MTRadical
		newRad.radicand = newRad.radicand?.finalized
		newRad.degree = newRad.degree?.finalized
		return newRad
	}
}

// MARK: - MTLargeOperator

/** A `MTMathAtom` of type `kMTMathAtom.largeOperator`. */
public class MTLargeOperator: MTMathAtom {
	/** Indicates whether the limits (if present) should be displayed
	 above and below the operator in display mode.  If limits is false
	 then the limits (if present) are displayed like a regular subscript/superscript.
	 */
	public var limits: Bool = false

	init(_ op: MTLargeOperator?) {
		super.init(op)
		type = .largeOperator
		limits = op!.limits
	}

	init(value: String, limits: Bool) {
		super.init(type: .largeOperator, value: value)
		self.limits = limits
	}
}

// MARK: - MTInner

/** An inner atom. This denotes an atom which contains a math list inside it. An inner atom
 has optional boundaries. Note: Only one boundary may be present, it is not required to have
 both. */
public class MTInner: MTMathAtom {
	/// The inner math list
	public var innerList: MTMathList?
	/// The left boundary atom. This must be a node of type kMTMathAtomBoundary
	public var leftBoundary: MTMathAtom? {
		didSet {
			if let left = leftBoundary, left.type != .boundary {
				leftBoundary = nil
				NSException(name: NSExceptionName(rawValue: "Error"), reason: "Left boundary must be of type .boundary").raise()
			}
		}
	}

	/// The right boundary atom. This must be a node of type kMTMathAtomBoundary
	public var rightBoundary: MTMathAtom? {
		didSet {
			if let right = rightBoundary, right.type != .boundary {
				rightBoundary = nil
				NSException(name: NSExceptionName(rawValue: "Error"), reason: "Right boundary must be of type .boundary").raise()
			}
		}
	}

	init(_ inner: MTInner?) {
		super.init(inner)
		type = .inner
		innerList = MTMathList(inner?.innerList)
		leftBoundary = MTMathAtom(inner?.leftBoundary)
		rightBoundary = MTMathAtom(inner?.rightBoundary)
	}

	override init() {
		super.init()
		type = .inner
	}

	override public var description: String {
		var string = "\\inner"
		if leftBoundary != nil {
			string += "[\(leftBoundary!.nucleus)]"
		}
		string += "{\(innerList!.description)}"
		if rightBoundary != nil {
			string += "[\(rightBoundary!.nucleus)]"
		}
		if superScript != nil {
			string += "^{\(superScript!.description)}"
		}
		if subScript != nil {
			string += "_{\(subScript!.description)}"
		}
		return string
	}

	override public var finalized: MTMathAtom {
		let newInner = super.finalized as! MTInner
		newInner.innerList = newInner.innerList?.finalized
		return newInner
	}
}

// MARK: - MTOverLIne

/** An atom with a line over the contained math list. */
public class MTOverLine: MTMathAtom {
	public var innerList: MTMathList?

	override public var finalized: MTMathAtom {
		let newOverline = MTOverLine(self)
		newOverline.innerList = newOverline.innerList?.finalized
		return newOverline
	}

	init(_ over: MTOverLine?) {
		super.init(over)
		type = .overline
		innerList = MTMathList(over!.innerList)
	}

	override init() {
		super.init()
		type = .overline
	}
}

// MARK: - MTUnderLine

/** An atom with a line under the contained math list. */
public class MTUnderLine: MTMathAtom {
	public var innerList: MTMathList?

	override public var finalized: MTMathAtom {
		let newUnderline = super.finalized as! MTUnderLine
		newUnderline.innerList = newUnderline.innerList?.finalized
		return newUnderline
	}

	init(_ under: MTUnderLine?) {
		super.init(under)
		type = .underline
		innerList = MTMathList(under?.innerList)
	}

	override init() {
		super.init()
		type = .underline
	}
}

// MARK: - MTAccent

public class MTAccent: MTMathAtom {
	public var innerList: MTMathList?

	override public var finalized: MTMathAtom {
		let newAccent = super.finalized as! MTAccent
		newAccent.innerList = newAccent.innerList?.finalized
		return newAccent
	}

	init(_ accent: MTAccent?) {
		super.init(accent)
		type = .accent
		innerList = MTMathList(accent?.innerList)
	}

	init(value: String) {
		super.init()
		type = .accent
		nucleus = value
	}
}

// MARK: - MTMathSpace

/** An atom representing space.
 Note: None of the usual fields of the `MTMathAtom` apply even though this
 class inherits from `MTMathAtom`. i.e. it is meaningless to have a value
 in the nucleus, subscript or superscript fields. */
public class MTMathSpace: MTMathAtom {
	/** The amount of space represented by this object in mu units. */
	public var space: CGFloat = 0

	/// Creates a new `MTMathSpace` with the given spacing.
	/// - parameter space: The amount of space in mu units.
	init(_ space: MTMathSpace?) {
		super.init(space)
		type = .space
		self.space = space?.space ?? 0
	}

	init(space: CGFloat) {
		super.init()
		type = .space
		self.space = space
	}
}

/**
 Styling of a line of math
 */
public enum MTLineStyle: Int, Comparable {
	/// Display style
	case display
	/// Text style (inline)
	case text
	/// Script style (for sub/super scripts)
	case script
	/// Script script style (for scripts of scripts)
	case scriptOfScript

	public func inc() -> MTLineStyle {
		let raw = rawValue + 1
		if let style = MTLineStyle(rawValue: raw) {
			return style
		}
		return .display
	}

	public var isNotScript: Bool {
		self < .script
	}

	public static func < (lhs: MTLineStyle, rhs: MTLineStyle) -> Bool {
		lhs.rawValue < rhs.rawValue
	}
}

// MARK: - MTMathStyle

/** An atom representing a style change.
 Note: None of the usual fields of the `MTMathAtom` apply even though this
 class inherits from `MTMathAtom`. i.e. it is meaningless to have a value
 in the nucleus, subscript or superscript fields. */
public class MTMathStyle: MTMathAtom {
	public var style: MTLineStyle = .display

	init(_ style: MTMathStyle?) {
		super.init(style)
		type = .style
		self.style = style!.style
	}

	init(style: MTLineStyle) {
		super.init()
		type = .style
		self.style = style
	}
}

// MARK: - MTMathColor

/** An atom representing an color element.
 Note: None of the usual fields of the `MTMathAtom` apply even though this
 class inherits from `MTMathAtom`. i.e. it is meaningless to have a value
 in the nucleus, subscript or superscript fields. */
public class MTMathColor: MTMathAtom {
	public var colorString: String = ""
	public var innerList: MTMathList?

	init(_ color: MTMathColor?) {
		super.init(color)
		type = .color
		colorString = color?.colorString ?? ""
		innerList = MTMathList(color?.innerList)
	}

	override init() {
		super.init()
		type = .color
	}

	override public var string: String {
		"\\color{\(colorString)}{\(innerList!.string)}"
	}

	override public var finalized: MTMathAtom {
		let newColor = super.finalized as! MTMathColor
		newColor.innerList = newColor.innerList?.finalized
		return newColor
	}
}

// MARK: - MTMathTextColor

/** An atom representing an textcolor element.
 Note: None of the usual fields of the `MTMathAtom` apply even though this
 class inherits from `MTMathAtom`. i.e. it is meaningless to have a value
 in the nucleus, subscript or superscript fields. */
public class MTMathTextColor: MTMathAtom {
	public var colorString: String = ""
	public var innerList: MTMathList?

	init(_ color: MTMathTextColor?) {
		super.init(color)
		type = .textcolor
		colorString = color?.colorString ?? ""
		innerList = MTMathList(color?.innerList)
	}

	override init() {
		super.init()
		type = .textcolor
	}

	override public var string: String {
		"\\textcolor{\(colorString)}{\(innerList!.string)}"
	}

	override public var finalized: MTMathAtom {
		let newColor = super.finalized as! MTMathTextColor
		newColor.innerList = newColor.innerList?.finalized
		return newColor
	}
}

// MARK: - MTMathColorbox

/** An atom representing an colorbox element.
 Note: None of the usual fields of the `MTMathAtom` apply even though this
 class inherits from `MTMathAtom`. i.e. it is meaningless to have a value
 in the nucleus, subscript or superscript fields. */
public class MTMathColorbox: MTMathAtom {
	public var colorString = ""
	public var innerList: MTMathList?

	init(_ cbox: MTMathColorbox?) {
		super.init(cbox)
		type = .colorBox
		colorString = cbox?.colorString ?? ""
		innerList = MTMathList(cbox?.innerList)
	}

	override init() {
		super.init()
		type = .colorBox
	}

	override public var string: String {
		"\\colorbox{\(colorString)}{\(innerList!.string)}"
	}

	override public var finalized: MTMathAtom {
		let newColor = super.finalized as! MTMathColorbox
		newColor.innerList = newColor.innerList?.finalized
		return newColor
	}
}

/**
    Alignment for a column of MTMathTable
 */
public enum MTColumnAlignment {
	case left
	case center
	case right
}

// MARK: - MTMathTable

/** An atom representing an table element. This atom is not like other
 atoms and is not present in TeX. We use it to represent the `\halign` command
 in TeX with some simplifications. This is used for matrices, equation
 alignments and other uses of multiline environments.

 The cells in the table are represented as a two dimensional array of
 `MTMathList` objects. The `MTMathList`s could be empty to denote a missing
 value in the cell. Additionally an array of alignments indicates how each
 column will be aligned.
 */
public class MTMathTable: MTMathAtom {
	/// The alignment for each column (left, right, center). The default alignment
	/// for a column (if not set) is center.
	public var alignments = [MTColumnAlignment]()
	/// The cells in the table as a two dimensional array.
	public var cells = [[MTMathList]]()
	/// The name of the environment that this table denotes.
	public var environment = ""
	/// Spacing between each column in mu units.
	public var interColumnSpacing: CGFloat = 0
	/// Additional spacing between rows in jots (one jot is 0.3 times font size).
	/// If the additional spacing is 0, then normal row spacing is used are used.
	public var interRowAdditionalSpacing: CGFloat = 0

	override public var finalized: MTMathAtom {
		let table = super.finalized as! MTMathTable
		for var row in table.cells {
			for i in 0 ..< row.count {
				row[i] = row[i].finalized
			}
		}
		return table
	}

	init(environment: String?) {
		super.init()
		type = .table
		self.environment = environment ?? ""
	}

	init(_ table: MTMathTable) {
		super.init(table)
		type = .table
		alignments = table.alignments
		interRowAdditionalSpacing = table.interRowAdditionalSpacing
		interColumnSpacing = table.interColumnSpacing
		environment = table.environment
		var cellCopy = [[MTMathList]]()
		for row in table.cells {
			var newRow = [MTMathList]()
			for col in row {
				newRow.append(MTMathList(col)!)
			}
			cellCopy.append(newRow)
		}
		cells = cellCopy
	}

	override init() {
		super.init()
		type = .table
	}

	/// Set the value of a given cell. The table is automatically resized to contain this cell.
	public func set(cell list: MTMathList, forRow row: Int, column: Int) {
		if cells.count <= row {
			for _ in cells.count ... row {
				cells.append([])
			}
		}
		let rows = cells[row].count
		if rows <= column {
			for _ in rows ... column {
				cells[row].append(MTMathList())
			}
		}
		cells[row][column] = list
	}

	/// Set the alignment of a particular column. The table is automatically resized to
	/// contain this column and any new columns added have their alignment set to center.
	public func set(alignment: MTColumnAlignment, forColumn col: Int) {
		if alignments.count <= col {
			for _ in alignments.count ... col {
				alignments.append(MTColumnAlignment.center)
			}
		}

		alignments[col] = alignment
	}

	/// Gets the alignment for a given column. If the alignment is not specified it defaults
	/// to center.
	public func get(alignmentForColumn col: Int) -> MTColumnAlignment {
		if alignments.count <= col {
			MTColumnAlignment.center
		} else {
			alignments[col]
		}
	}

	public var numColumns: Int {
		var numberOfCols = 0
		for row in cells {
			numberOfCols = max(numberOfCols, row.count)
		}
		return numberOfCols
	}

	public var numRows: Int {
		cells.count
	}
}

// MARK: - MTMathList

public extension MTMathList {
	override var description: String {
		atoms.description
	}

	/// converts the MTMathList to a string form. Note: This is not the LaTeX form.
	var string: String {
		description
	}
}

/** A representation of a list of math objects.

    This list can be constructed directly or built with
    the help of the MTMathListBuilder. It is not required that the mathematics represented make sense
    (i.e. this can represent something like "x 2 = +". This list can be used for display using MTLine
    or can be a list of tokens to be used by a parser after finalizedMathList is called.

    Note: This class is for **advanced** usage only.
 */
public class MTMathList: NSObject {
	init?(_ list: MTMathList?) {
		guard let list else { return nil }
		for atom in list.atoms {
			atoms.append(atom.copy())
		}
	}

	/// A list of MathAtoms
	public var atoms = [MTMathAtom]()

	/// Create a new math list as a final expression and update atoms
	/// by combining like atoms that occur together and converting unary operators to binary operators.
	/// This function does not modify the current MTMathList
	public var finalized: MTMathList {
		let finalizedList = MTMathList()
		let zeroRange = NSMakeRange(0, 0)

		var prevNode: MTMathAtom? = nil
		for atom in atoms {
			let newNode = atom.finalized

			if NSEqualRanges(zeroRange, atom.indexRange) {
				let index = prevNode == nil ? 0 : prevNode!.indexRange.location + prevNode!.indexRange.length
				newNode.indexRange = NSMakeRange(index, 1)
			}

			switch newNode.type {
				case .binaryOperator:
					if isNotBinaryOperator(prevNode) {
						newNode.type = .unaryOperator
					}
				case .relation, .punctuation, .close:
					if prevNode != nil, prevNode!.type == .binaryOperator {
						prevNode!.type = .unaryOperator
					}
				case .number:
					if prevNode != nil, prevNode!.type == .number, prevNode!.subScript == nil, prevNode!.superScript == nil {
						prevNode!.fuse(with: newNode)
						continue // skip the current node, we are done here.
					}
				default: break
			}
			finalizedList.add(newNode)
			prevNode = newNode
		}
		if prevNode != nil, prevNode!.type == .binaryOperator {
			prevNode!.type = .unaryOperator
		}
		return finalizedList
	}

	public init(atoms: [MTMathAtom]) {
		self.atoms.append(contentsOf: atoms)
	}

	public init(atom: MTMathAtom) {
		atoms.append(atom)
	}

	override public init() {
		super.init()
	}

	func NSParamException(_ param: Any?) {
		if param == nil {
			NSException(name: NSExceptionName(rawValue: "Error"), reason: "Parameter cannot be nil").raise()
		}
	}

	func NSIndexException(_ array: [Any], index: Int) {
		guard !array.indices.contains(index) else { return }
		NSException(name: NSExceptionName(rawValue: "Error"), reason: "Index \(index) out of bounds").raise()
	}

	/// Add an atom to the end of the list.
	/// - parameter atom: The atom to be inserted. This cannot be `nil` and cannot have the type `kMTMathAtomBoundary`.
	/// - throws NSException if the atom is of type `kMTMathAtomBoundary`
	public func add(_ atom: MTMathAtom?) {
		guard let atom else { return }
		if isAtomAllowed(atom) {
			atoms.append(atom)
		} else {
			NSException(name: NSExceptionName(rawValue: "Error"), reason: "Cannot add atom of type \(atom.type.rawValue) into mathlist").raise()
		}
	}

	/// Inserts an atom at the given index. If index is already occupied, the objects at index and beyond are
	/// shifted by adding 1 to their indices to make room. An insert to an `index` greater than the number of atoms
	/// is ignored.  Insertions of nil atoms is ignored.
	/// - parameter atom: The atom to be inserted. This cannot be `nil` and cannot have the type `kMTMathAtom.boundary`.
	/// - parameter index: The index where the atom is to be inserted. The index should be less than or equal to the
	///  number of elements in the math list.
	/// - throws NSException if the atom is of type kMTMathAtomBoundary
	public func insert(_ atom: MTMathAtom?, at index: Int) {
		// NSParamException(atom)
		guard let atom, atoms.indices.contains(index) || index == atoms.endIndex else { return }
		// guard self.atoms.endIndex >= index else { NSIndexException(); return }
		if isAtomAllowed(atom) {
			// NSIndexException(self.atoms, index: index)
			atoms.insert(atom, at: index)
		} else {
			NSException(name: NSExceptionName(rawValue: "Error"), reason: "Cannot add atom of type \(atom.type.rawValue) into mathlist").raise()
		}
	}

	/// Append the given list to the end of the current list.
	/// - parameter list: The list to append.
	public func append(_ list: MTMathList?) {
		guard let list else { return }
		atoms += list.atoms
	}

	/** Removes the last atom from the math list. If there are no atoms in the list this does nothing. */
	public func removeLastAtom() {
		if !atoms.isEmpty {
			atoms.removeLast()
		}
	}

	/// Removes the atom at the given index.
	/// - parameter index: The index at which to remove the atom. Must be less than the number of atoms
	/// in the list.
	public func removeAtom(at index: Int) {
		NSIndexException(atoms, index: index)
		atoms.remove(at: index)
	}

	/** Removes all the atoms within the given range. */
	public func removeAtoms(in range: ClosedRange<Int>) {
		NSIndexException(atoms, index: range.lowerBound)
		NSIndexException(atoms, index: range.upperBound)
		atoms.removeSubrange(range)
	}

	func isAtomAllowed(_ atom: MTMathAtom?) -> Bool {
		atom?.type != .boundary
	}
}

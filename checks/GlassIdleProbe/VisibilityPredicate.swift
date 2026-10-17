import Foundation

func canRenderWindow(
	appHidden: Bool,
	windowVisible: Bool,
	miniaturized: Bool,
	occlusionVisible: Bool
) -> Bool {
	!appHidden && windowVisible && !miniaturized && occlusionVisible
}

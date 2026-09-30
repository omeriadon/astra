#if os(macOS)
	import AppKit
	import SpriteKit

	@MainActor
	enum MiniAstraOpeningAnimation {
		static func panel(
			for window: NSWindow,
			from cursor: NSPoint,
			completion: @escaping @MainActor () -> Void
		) -> NSPanel? {
			guard let view = window.contentView?.superview else { return nil }
			view.layoutSubtreeIfNeeded()
			guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
			view.cacheDisplay(in: view.bounds, to: bitmap)
			guard let image = bitmap.cgImage else { return nil }

			let destination = window.frame
			let frame = destination.union(NSRect(x: cursor.x - 8, y: cursor.y - 8, width: 16, height: 16))
				.insetBy(dx: -32, dy: -32)
			let panel = NSPanel(
				contentRect: frame,
				styleMask: [.borderless, .nonactivatingPanel],
				backing: .buffered,
				defer: false
			)
			panel.isOpaque = false
			panel.backgroundColor = .clear
			panel.hasShadow = false
			panel.ignoresMouseEvents = true
			panel.hidesOnDeactivate = false
			panel.isReleasedWhenClosed = false
			panel.level = window.level
			panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

			let scene = SKScene(size: frame.size)
			scene.backgroundColor = .clear
			let sprite = SKSpriteNode(texture: SKTexture(cgImage: image))
			sprite.size = destination.size
			sprite.position = CGPoint(x: destination.midX - frame.minX, y: destination.midY - frame.minY)
			sprite.color = .white
			sprite.colorBlendFactor = 1
			scene.addChild(sprite)

			let origin = SIMD2<Float>(
				Float((cursor.x - destination.minX) / destination.width),
				Float((cursor.y - destination.minY) / destination.height)
			)
			let source = (0 ... 8).flatMap { row in
				(0 ... 8).map { column in
					SIMD2<Float>(Float(column) / 8, Float(row) / 8)
				}
			}
			let warps = (0 ... 24).map { index in
				let progress = Float(index) / 24
				return SKWarpGeometryGrid(
					columns: 8,
					rows: 8,
					sourcePositions: source,
					destinationPositions: positions(source: source, origin: origin, progress: progress)
				)
			}
			let times = (0 ... 24).map { NSNumber(value: 0.12 + Double($0) / 24 * 0.72) }
			guard let warp = SKAction.animate(withWarps: warps, times: times) else { return nil }
			sprite.warpGeometry = warps[0]
			sprite.run(warp, completion: completion)
			sprite.run(.sequence([
				.wait(forDuration: 0.16),
				.colorize(withColorBlendFactor: 0, duration: 0.3),
			]))

			let star = SKShapeNode(circleOfRadius: 2)
			star.position = CGPoint(x: cursor.x - frame.minX, y: cursor.y - frame.minY)
			star.fillColor = .white
			star.strokeColor = .white
			star.glowWidth = 6
			star.zPosition = 1
			scene.addChild(star)
			star.run(.sequence([
				.wait(forDuration: 0.12),
				.group([
					.move(to: sprite.position, duration: 0.3),
					.scale(to: 2, duration: 0.3),
					.fadeOut(withDuration: 0.3),
				]),
				.removeFromParent(),
			]))

			let skView = SKView(frame: NSRect(origin: .zero, size: frame.size))
			skView.allowsTransparency = true
			panel.contentView = skView
			skView.presentScene(scene)

			#if DEBUG
				let start = positions(source: [SIMD2<Float>(0.5, 0.5)], origin: origin, progress: 0)[0]
				assert(simd_distance(start, origin) < 0.0001)
				let end = positions(source: source, origin: origin, progress: 1)
				assert(zip(source, end).allSatisfy { simd_distance($0, $1) < 0.0001 })
			#endif
			return panel
		}

		private static func positions(
			source: [SIMD2<Float>],
			origin: SIMD2<Float>,
			progress: Float
		) -> [SIMD2<Float>] {
			let travel = progress * progress * (3 - 2 * progress)
			let center = origin + (SIMD2<Float>(0.5, 0.5) - origin) * travel
			let scale = 0.004 + 0.996 * travel
			let bend = sin(.pi * progress)
			return source.map { point in
				let offset = point - SIMD2<Float>(0.5, 0.5)
				let waist = 1 - 0.8 * bend * (1 - abs(offset.y) * 2)
				return center + SIMD2<Float>(
					offset.x * scale * waist + 0.16 * bend * sin(.pi * point.y),
					offset.y * scale
				)
			}
		}
	}
#endif

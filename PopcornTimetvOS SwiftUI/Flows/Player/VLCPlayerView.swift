//
//  VLCPlayerView.swift
//  PopcornTimetvOS SwiftUI
//
//  Created by Alexandru Tudose on 21.06.2021.
//  Copyright © 2021 PopcornTime. All rights reserved.
//

import SwiftUI
import TVVLCKit

struct VLCPlayerView: UIViewRepresentable {
    var mediaplayer = VLCMediaPlayer()
    
    var onTap: (() -> Void)?
    var onPlayPause: (() -> Void)?
    var onMove: ((_ direction: MoveCommandDirection) -> Void)?
    var onSwipeUp: (() -> Void)?
    var onSwipeDown: (() -> Void)?
    var onTouchLocationDidChange: ((SiriRemoteGestureRecognizer) -> Void)?
    var onPositionSliderDrag: ((Float) -> Void)?
    var onExit: (() -> Void)?
    var focused = true
    
    func makeUIView(context: Context) -> FocusedView {
        let view = FocusedView()
        mediaplayer.drawable = view
        context.coordinator.addGestures(view: view)
        return view
    }
    
    func updateUIView(_ uiView: FocusedView, context: Context) {
        mediaplayer.drawable = uiView
        if (uiView.shouldFocus != focused) {
//            uiView.shouldFocus = context.environment.isFocused
            uiView.shouldFocus = focused
//            uiView.setNeedsFocusUpdate()
//            uiView.updateFocusIfNeeded()
        }
    }
    
    func makeCoordinator() -> VLCPlayerCoordinator {
        let coordinator = VLCPlayerCoordinator()
        coordinator.onPlayPause = onPlayPause
        coordinator.onExit = onExit
        coordinator.onSwipeDown = onSwipeDown
        coordinator.onSwipeUp = onSwipeUp
        coordinator.onTap = onTap
        coordinator.onMove = onMove
        coordinator.onTouchLocationDidChange = onTouchLocationDidChange
        coordinator.onPositionSliderDrag = onPositionSliderDrag
        return coordinator
    }
    
    class FocusedView: UIView {
        var shouldFocus: Bool = true
        
//        override var canBecomeFocused: Bool {
//            return shouldFocus
//        }
    }
    
    
    class VLCPlayerCoordinator: NSObject, UIGestureRecognizerDelegate {
        var onPlayPause: (() -> Void)?
        var onExit: (() -> Void)?
        var onMove: ((_ direction: MoveCommandDirection) -> Void)?
        var onSwipeUp: (() -> Void)?
        var onSwipeDown: (() -> Void)?
        var onTap: (() -> Void)?
        var onTouchLocationDidChange: ((SiriRemoteGestureRecognizer) -> Void)?
        var onPositionSliderDrag: ((Float) -> Void)?
        var lastTranslation: CGFloat = .zero
        var progressBarWidth: CGFloat = 1000.0
        
        func addGestures(view: UIView) {
            let swipeDownGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipeDownGesture))
            swipeDownGesture.direction = .down
            swipeDownGesture.cancelsTouchesInView = false
            swipeDownGesture.delegate = self
            view.addGestureRecognizer(swipeDownGesture)
            
//            let swipeUpGesture = UISwipeGestureRecognizer(target: self, action: #selector(swipeUpGesture))
//            swipeUpGesture.direction = .up
//            swipeUpGesture.delegate = self
//            view.addGestureRecognizer(swipeUpGesture)
            
            let gesture = SiriRemoteGestureRecognizer(target: self, action: #selector(touchLocationDidChange(_:)))
            gesture.delegate = self
            gesture.require(toFail: swipeDownGesture)
//            gesture.require(toFail: swipeUpGesture)
            view.addGestureRecognizer(gesture)
            
            let menuGesture = SiriRemoteButtonRecognizer(target: self, action: #selector(onMenuAction), allowedPressTypes: [.menu])
            menuGesture.delegate = self
            view.addGestureRecognizer(menuGesture)
            

            let playPause = SiriRemoteButtonRecognizer(target: self, action: #selector(onPlayPauseAction), allowedPressTypes: [.playPause])
            playPause.delegate = self
            view.addGestureRecognizer(playPause)

            let moveDirection = SiriRemoteButtonRecognizer(target: self, action: #selector(onMoveAction(gesture:)), allowedPressTypes: [.downArrow, .leftArrow, .rightArrow, .upArrow])
            view.addGestureRecognizer(moveDirection)
            
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(onPanGestureAction(gesture:)))
            gesture.delegate = self
            gesture.requiresExclusiveTouchType = false
            view.addGestureRecognizer(panGesture)
        }
        
        @objc func touchLocationDidChange(_ gesture: SiriRemoteGestureRecognizer) {
            if (gesture.touchLocation == .unknown && gesture.isClick && gesture.state == .ended) {
                onTap?()
            } else {
                onTouchLocationDidChange?(gesture)
            }
        }
        
        @objc func swipeUpGesture() {
            onSwipeUp?()
        }
        
        @objc func swipeDownGesture() {
            onSwipeDown?()
        }
        
        @objc func onPlayPauseAction() {
            onPlayPause?()
        }
        
        @objc func onMenuAction() {
            onExit?()
        }
        
        @objc func onTapAction() {
            onTap?()
        }
        
        @objc func onMoveAction(gesture: SiriRemoteButtonRecognizer) {
            switch gesture.detectedType {
            case .downArrow: onMove?(.down)
            case .leftArrow: onMove?(.left)
            case .upArrow: onMove?(.up)
            case .rightArrow: onMove?(.right)
            default:
                break
            }
        }
        
        @objc func onPanGestureAction(gesture: UIPanGestureRecognizer) {
            let translation = gesture.translation(in: gesture.view)
            let offset = Float((translation.x - lastTranslation) / progressBarWidth / 8.0)
            
            switch gesture.state {
            case .cancelled:
                fallthrough
            case .ended:
                lastTranslation = 0.0
            case .began:
                fallthrough
            case .changed:
                onPositionSliderDrag?(offset)
                lastTranslation = translation.x
            default:
                return
            }
        }
        
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            return true
        }
    }
}
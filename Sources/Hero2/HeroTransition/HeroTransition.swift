import UIKit

open class HeroTransition: Transition {
  open override func animate() -> (dismissed: () -> Void, presented: () -> Void, completed: (Bool) -> Void) {
    guard let back = backgroundView, let front = foregroundView, let container = transitionContainer else {
      fatalError()
    }

    var contexts: [UIView: ViewTransitionContext] = [:]
    let isPresenting = isPresenting
    
    var dismissedOperations: [() -> Void] = []
    var presentedOperations: [() -> Void] = []
    var completionOperations: [(Bool) -> Void] = []
    
    var animatingViews: [UIView] = []
    
    var frontIdToView: [String: UIView] = [:]
    var backIdToView: [String: UIView] = [:]
    for view in front.flattendSubviews {
      if let heroID = view.heroID {
        frontIdToView[heroID] = view
      }
    }
    for view in back.flattendSubviews {
      if let heroID = view.heroID {
        backIdToView[heroID] = view
      }
    }
    
    func findMatchedSuperview(view: UIView) -> UIView? {
      var current = view
      while let superview = current.superview, !(superview is UIWindow) {
        if contexts[superview] != nil {
          return superview
        }
        current = superview
      }
      return nil
    }
    func processContext(views: [UIView], otherIdToView: [String: UIView], isFront: Bool) {
      for view in views {
        let heroID = view.heroID
        let modifiers = view.heroModifiers ?? []
        let other = heroID.flatMap { otherIdToView[$0] }
        let modifierState = viewStateFrom(modifiers: modifiers,
                                          isPresenting: isPresenting,
                                          isMatched: other != nil,
                                          isForeground: isFront)
        if other != nil || modifierState != ViewState() {
          let matchedSuperview = (modifierState.containerType ?? .parent) == .parent ? findMatchedSuperview(view: view) : nil
          let sourceState = sourceViewStateFrom(view: view, modifierState: modifierState)
          let targetState = targetViewStateFrom(view: other ?? view, modifierState: modifierState)
          let originalState = originalViewStateFrom(view: view, sourceState: sourceState, targetState: targetState)
          contexts[view] = ViewTransitionContext(id: heroID,
                                                 isFront: isFront,
                                                 targetView: other,
                                                 matchedSuperView: matchedSuperview,
                                                 snapshotView: nil,
                                                 sourceState: sourceState,
                                                 targetState: targetState,
                                                 originalState: originalState)
          animatingViews.append(view)
        }
      }
    }
    processContext(views: back.flattendSubviews, otherIdToView: frontIdToView, isFront: false)
    processContext(views: front.flattendSubviews, otherIdToView: backIdToView, isFront: true)
    
    // generate snapshot (must be done in reverse, so that child is hidden before parent's snapshot is taken)
    for view in animatingViews.reversed() {
      if (contexts[view]?.targetState.snapshotType ?? .default) == .default {
        let snap = view.snapshotView(afterScreenUpdates: true)!
        snap.layer.shadowColor = view.layer.shadowColor
        snap.layer.shadowRadius = view.layer.shadowRadius
        snap.layer.shadowOffset = view.layer.shadowOffset
        snap.layer.cornerRadius = view.layer.cornerRadius
        snap.clipsToBounds = view.clipsToBounds
        contexts[view]?.snapshotView = snap
      } else {
        let placeholderView = UIView()
        view.superview?.insertSubview(placeholderView, aboveSubview: view)
        contexts[view]?.snapshotView = view
        contexts[view]?.placeholderView = placeholderView
      }
      if contexts[view]?.targetState.overlayColor != nil || contexts[view]?.sourceState.overlayColor != nil {
        contexts[view]?.snapshotView?.addOverlayView()
      }
      view.isHidden = true
    }
    
    let duration = animator!.duration
    for view in animatingViews {
      let viewContext = contexts[view]!
      let viewSnap = viewContext.snapshotView!
      let viewContainer = viewContext.matchedSuperView.flatMap { contexts[$0]?.snapshotView } ?? container
      viewContainer.addSubview(viewSnap)
      viewSnap.isHidden = false
      dismissedOperations.append {
        applyState(viewSnap: viewSnap, presented: false, shouldApplyDelay: !isPresenting, animationDuration: duration, viewContext: viewContext)
      }
      presentedOperations.append {
        applyState(viewSnap: viewSnap, presented: true, shouldApplyDelay: isPresenting, animationDuration: duration, viewContext: viewContext)
      }
      completionOperations.append { _ in
        if let placeholderView = viewContext.placeholderView {
          if placeholderView.superview != container {
            placeholderView.superview?.insertSubview(viewSnap, belowSubview: placeholderView)
          }
          placeholderView.removeFromSuperview()
          viewSnap.removeOverlayView()
          apply(viewState: viewContext.originalState, to: viewSnap)
        } else {
          viewSnap.removeFromSuperview()
          view.isHidden = false
        }
      }
    }
    
    let dismissed: () -> Void = {
      for op in dismissedOperations {
        op()
      }
    }

    let presented: () -> Void = {
      for op in presentedOperations {
        op()
      }
    }
    
    let completion: (Bool) -> Void = { finished in
      for op in completionOperations {
        op(finished)
      }
    }
    return (dismissed, presented, completion)
  }
}

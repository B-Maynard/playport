// SPDX-License-Identifier: GPL-3.0-or-later
// A view's alpha animated by Core Animation, as UIView.animate would: the model alpha is
// set at once and the layer's opacity eases from the value on screen. No closure is handed
// to UIKit, so Swift's isolation check (which carries the workstation's path into the
// binary under Swift 6.4) is never emitted.

import UIKit

@MainActor
enum ViewFade {
    static func fade(_ view: UIView, to alpha: CGFloat, duration: TimeInterval, delay: TimeInterval = 0,
                     completion: (@MainActor () -> Void)? = nil) {
        let from = view.layer.presentation()?.opacity ?? view.layer.opacity
        view.alpha = alpha
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = Float(alpha)
        anim.duration = duration
        anim.beginTime = CACurrentMediaTime() + delay
        anim.fillMode = .backwards
        view.layer.add(anim, forKey: "fade")
        if let completion {
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(delay + duration))
                completion()
            }
        }
    }
}

//
// KeyboardBottomConstraint.swift
//
// WidgetKit, Copyright (c) 2018 M8 Labs (http://m8labs.com)
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import UIKit

public class KeyboardBottomConstraint: NSLayoutConstraint, ObserversStorageProtocol {
    
    @IBOutlet weak var view: UIView!
    
    @objc public var animated = true
    @objc public var reversed = false
    
    @objc public var keyboardMargin: CGFloat = 0
    
    public var observers: [Any] = []
    private var initialHeight: CGFloat = 0
    
    func adjustHeight(with notification: Notification, hide: Bool) {
        precondition(view != nil, "You need to set `\(KeyboardBottomConstraint.self).view` outlet.")
        guard let kbRect = (notification.userInfo?[UIKeyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        guard hide || abs(initialHeight) < kbRect.height else { return }
        let h = hide ? initialHeight : (kbRect.height + keyboardMargin)
        guard h != constant else { return }
        constant = (reversed ? -1 : 1) * h
        if animated {
            guard let duration = (notification.userInfo?[UIKeyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue else { return }
            guard let curve = (notification.userInfo?[UIKeyboardAnimationCurveUserInfoKey] as? NSNumber)?.uintValue else { return }
            UIView.animate(withDuration: duration, delay: 0, options: UIViewAnimationOptions(rawValue: curve), animations: {
                self.view.superview!.layoutIfNeeded()
            })
        }
    }
    
    public func setupObservers() {
        observers = [
            NSNotification.Name.UIKeyboardWillChangeFrame.addObserver { [weak self] notification in
                self?.adjustHeight(with: notification, hide: false)
            },
            NSNotification.Name.UIKeyboardWillShow.addObserver { [weak self] notification in
                self?.adjustHeight(with: notification, hide: false)
            },
            NSNotification.Name.UIKeyboardWillHide.addObserver { [weak self] notification in
                self?.adjustHeight(with: notification, hide: true)
            }
        ]
    }
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        initialHeight = constant
        setupObservers()
    }
}

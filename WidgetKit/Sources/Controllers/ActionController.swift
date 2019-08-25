//
// ActionController.swift
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

public class ActionArgs: NSObject {
    
    @objc public var content: Any?
    @objc public var params: Any?
    
    init(content: Any?, params: Any?) {
        self.content = content
        self.params = params
    }
}

open class ActionController: CustomIBObject {
    
    static let targetSelectorSignatureFormat = "%@:sender:"
    
    @IBOutlet public var target: NSObject?
    @IBOutlet public weak var sender: NSObject?
    @IBOutlet public weak var cancelButton: UIButton?
    @IBOutlet public weak var form: ContentFormProtocol?
    @IBOutlet public weak var serviceProvider: ServiceProvider?
    @IBOutlet public weak var nextActionController: ActionController?
    
    @objc public var actionName: String!
    @objc public var elseActionName: String?
    @objc public var predicateFormat: String?
    @objc public var actionDelay: Double = 0.0
    @objc public var serviceProviderClassName: String?
    
    @objc lazy public private(set) var status = ActionStatusController(owner: self)
    
    @objc open var params: Any? {
        return form?.formValue
    }
    
    @objc open var content: Any? {
        return viewController.content
    }
    
    var predicate: NSPredicate? {
        guard let format = predicateFormat else { return nil }
        return NSPredicate(format: format)
    }
    
    var predicateValue: Bool {
        return predicate?.evaluate(with: viewController.vars) ?? true
    }
    
    var resolvedActionName: String? {
        return predicateValue ? actionName : elseActionName
    }
    
    var resolvedServiceProvider: ServiceProvider {
        var sp = serviceProvider
        if sp == nil {
            if let className = serviceProviderClassName ?? viewController?.serviceProviderClassName {
                sp = NSObject.create(withClassName: className) as? ServiceProvider
                (sp as? StandardServiceProvider)?.widget = widget
            }
        }
        return sp ?? StandardServiceProvider.default
    }
    
    var targetSelector: Selector? {
        guard let resolvedActionName = resolvedActionName else { return nil }
        let selector = Selector(String(format: ActionController.targetSelectorSignatureFormat, resolvedActionName))
        return selector
    }
    
    var cancelSelector: Selector? {
        guard let resolvedActionName = resolvedActionName else { return nil }
        let selector = Selector("cancel" + String(format: ActionController.targetSelectorSignatureFormat, resolvedActionName).capitalized)
        return selector
    }
    
    func performServiceAction(with object: Any?) {
        guard let actionName = resolvedActionName else {
            return print("Action for the \(self) was resolved to nil.")
        }
        let service = resolvedServiceProvider
        status.setupObservers()
        let args = ActionArgs(content: content, params: object ?? params)
        (viewController as? SchemeDiagnosticsProtocol)?.beforeAction?(actionName, content: args, sender: self)
        let selector = targetSelector
        if service.responds(to: selector) {
            service.perform(selector, with: args, with: self)
        } else {
            service.performAction(actionName, with: args, from: self, completion: nil)
        }
    }
    
    func cancelServiceAction(with object: Any?) {
        guard viewController != nil else {
            return print("Warning: view controller for this action doesn't exist.")
        }
        let service = resolvedServiceProvider
        let selector = cancelSelector
        let args = ActionArgs(content: content, params: object ?? params)
        if service.responds(to: selector) {
            service.perform(selector, with: args)
        } else if let actionName = resolvedActionName {
            service.cancelRequest(for: actionName, with: args, from: self)
        }
    }
    
    private func _performAction(with object: Any?) {
        if let target = target {
            let selector = targetSelector
            if target.responds(to: selector) {
                target.perform(selector, with: object, with: self)
            } else {
                performServiceAction(with: object)
            }
        } else {
            performServiceAction(with: object)
        }
    }
    
    @objc open func performAction(with object: Any? = nil) {
        guard viewController != nil else {
            return print("Warning: view controller for this action doesn't exist.")
        }
        guard form == nil || form!.formValue != nil else {
            return print("Warning: Form exists but value was nil - aborting action \(actionName!).")
        }
        after(actionDelay) {
            self._performAction(with: object)
        }
    }
    
    @objc open func cancelAction(with object: Any? = nil) {
        cancelServiceAction(with: object)
    }
    
    open override func setup() {
        form?.actionController = self
        cancelButton?.addTarget(self, action: #selector(cancelAction), for: .touchUpInside)
        super.setup()
    }
}

extension ActionController {
    
    @IBAction func defaultHandler(_ sender: Any?) {
        performAction()
    }
}

extension ActionController: ActionStatusControllerDelegate {
    
    @discardableResult
    @objc open func statusChanged(_ status: ActionStatusController, result: Any?, error: Error?) -> Bool {
        guard status.isSuccess else { return true }
        nextActionController?.performAction(with: result)
        return true
    }
}

open class ButtonActionController: ActionController {
    
    var button: UIButton? {
        return sender as? UIButton
    }
    
    open override func setup() {
        super.setup()
        button?.addTarget(self, action: #selector(defaultHandler(_:)), for: .touchUpInside)
    }
}

open class BarButtonActionController: ActionController {
    
    var barButtonItem: UIBarButtonItem? {
        return sender as? UIBarButtonItem
    }
    
    open override func setup() {
        super.setup()
        barButtonItem?.target = self
        barButtonItem?.action = #selector(defaultHandler(_:))
    }
}

open class TableRefreshActionController: ActionController {
    
    var tableView: UITableView? {
        return sender as? UITableView
    }
    
    open override func setup() {
        super.setup()
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(defaultHandler(_:)), for: .valueChanged)
        tableView?.refreshControl = refreshControl
    }
}

open class OnLoadActionController: ActionController {
    
    open override func setup() {
        super.setup()
        perform(#selector(performAction), with: nil, afterDelay: 0)
    }
}

open class TimerActionController: ActionController {
    
    @objc public var interval: TimeInterval = 60
    @objc public var runImmediately: Bool = true
    
    open override func performAction(with object: Any? = nil) {
        guard viewController != nil else {
            return NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(performAction), object: nil)
        }
        super.performAction()
        perform(#selector(performAction), with: nil, afterDelay: interval)
    }
    
    open override func setup() {
        super.setup()
        perform(#selector(performAction), with: nil, afterDelay: runImmediately ? 0 : interval)
    }
}

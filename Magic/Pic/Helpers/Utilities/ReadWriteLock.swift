//
//  ReadWriteLock.swift
//  Magic
//
//  Created by CoderWan on 2026/4/3.
//

import Foundation

@propertyWrapper
public class ReadWriteLock<T> {
    private var _wrappedValue: T
    private let lock = NSRecursiveLock()
    
    
    public var wrappedValue: T {
        get { self.read { $0 } }
        set { self.update { $0 = newValue } }
    }
    
    public var projectedValue: ReadWriteLock<T> { self }
    
    public init(wrappedValue: T) {
        self._wrappedValue = wrappedValue
    }
    
    @discardableResult
    final public func read<U>(_ block: (T) throws -> U) rethrows -> U {
        self.lock.lock()
        defer { self.lock.unlock() }
        return try block(self._wrappedValue)
    }
    
    @discardableResult
    final public func update<U>(_ block: (inout T) throws -> U) rethrows -> U {
        self.lock.lock()
        defer { self.lock.unlock() }
        return try block(&self._wrappedValue)
    }
}

// MARK: - Numeric
public extension ReadWriteLock where T: Numeric {
    @discardableResult
    final func increment() -> T {
        self.update { n in
            n += 1
            return n
        }
    }
    
    @discardableResult
    final func decrement() -> T {
        self.update { n in
            n -= 1
            return n
        }
    }
}

// MARK: - Dictionary
public extension ReadWriteLock where T == Dictionary<String, Any> {
    @discardableResult
    final func safeValue<S>(for key: String, block: () -> S) -> S {
        self.lock.lock()
        defer { self.lock.unlock() }
        if let index = self._wrappedValue.index(forKey: key) {
            if let obj = self._wrappedValue[index].value as? S {
                return obj
            }
        }
        let value = block()
        self._wrappedValue.updateValue(value, forKey: key)
        return value
    }
}

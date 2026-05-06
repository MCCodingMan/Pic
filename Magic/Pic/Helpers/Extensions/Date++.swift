//
//  Date++.swift
//  Magic
//
//  Created by CoderWan on 2026/4/2.
//

import Foundation
extension Date {
    /// 当前时间是否比参数时间更新
    /// - Parameter date: 比较的时间
    /// - Returns: Bool 结果
    nonisolated func isNewerOrSameThanDate(date: Date) -> Bool {
        let nowSec = self.timeIntervalSince1970
        let dateSec = date.timeIntervalSince1970
        
        return nowSec >= dateSec
    }
}

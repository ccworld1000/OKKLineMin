//
//  OKKLineSwift
//
//  Copyright © 2016年 Herb - https://github.com/Herb-Sun/OKKLineSwift
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation

struct OKEMAModel {
    
    let indicatorType: OKIndicatorType
    let klineModels: [OKKLineModel]
    
    init(indicatorType: OKIndicatorType, klineModels: [OKKLineModel]) {
        self.indicatorType = indicatorType
        self.klineModels = klineModels
    }
    
    public func fetchDrawEMAData(drawRange: NSRange? = nil) -> [OKKLineModel] {
        
        var datas = [OKKLineModel]()
        
        guard klineModels.count > 0 else {
            return datas
        }
        
        for (index, model) in klineModels.enumerated() {
            
            switch indicatorType {
            case .EMA(let days):
                
                var values = [Double?]()
                
                for (idx, day) in days.enumerated() {
                    
                    let previousEMA: Double? = index > 0 ? datas[index - 1].EMAs?[idx] : nil
                    values.append(handleEMA(day: day, model: model, index: index, previousEMA: previousEMA))
                }
                model.EMAs = values
            default:
                break
            }
            datas.append(model)
        }
        
        if let range = drawRange {
            return Array(datas[range.location..<range.location+range.length])
        } else {
            return datas
        }
    }
    
    private func handleEMA(day: Int, model: OKKLineModel, index: Int, previousEMA: Double?) -> Double? {
        if day <= 0 || index < (day - 1) {
            return nil
        } else {
            if previousEMA != nil {
                return Double(day - 1) / Double(day + 1) * previousEMA! + 2 / Double(day + 1) * model.close
            } else {
                return 2 / Double(day + 1) * model.close
            }
        }
    }
}

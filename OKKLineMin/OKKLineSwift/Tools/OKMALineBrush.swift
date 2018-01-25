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

#if os(iOS) || os(tvOS)
    import UIKit
#else
    import Cocoa
#endif
import CoreGraphics

enum OKBrushType {
    case MA(Int)
    case EMA(Int)
    case MA_VOLUME(Int)
    case EMA_VOLUME(Int)
}

class OKMALineBrush {
    
    public var calFormula: ((Int, OKKLineModel) -> CGPoint?)?
    public var brushType: OKBrushType
    private var context: CGContext
    private var firstValueIndex: Int?
    private let configuration = OKConfiguration.sharedConfiguration
    

    init(brushType: OKBrushType, context: CGContext) {
        self.brushType = brushType
        self.context = context
        
        context.setLineWidth(configuration.theme.indicatorLineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        switch brushType {
        case .MA(let day):
            context.setStrokeColor(configuration.theme.MAColor(day: day).cgColor)
        case .EMA(let day):
            context.setStrokeColor(configuration.theme.EMAColor(day: day).cgColor)
        case .MA_VOLUME(let day):
            context.setStrokeColor(configuration.theme.MAColor(day: day).cgColor)
        case .EMA_VOLUME(let day):
            context.setStrokeColor(configuration.theme.EMAColor(day: day).cgColor)
        }
    }
    
    public func draw(drawModels: [OKKLineModel]) {
    
        for (index, model) in drawModels.enumerated() {
            
            if let point = calFormula?(index, model) {
                
                if firstValueIndex == nil {
                    firstValueIndex = index
                }
                
                if firstValueIndex == index {
                    context.move(to: point)
                } else {
                    context.addLine(to: point)
                }
            }
        }
        context.strokePath()
    }
}


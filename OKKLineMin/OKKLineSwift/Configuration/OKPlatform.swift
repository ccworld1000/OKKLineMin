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

import UIKit
import SnapKit
import CoreFoundation

public typealias OKFont = UIFont
public typealias OKColor = UIColor
public typealias OKEdgeInsets = UIEdgeInsets

func OKGraphicsGetCurrentContext() -> CGContext? {
    return UIGraphicsGetCurrentContext()
}

extension OKFont {
    
    public class func systemFont(size: CGFloat) -> OKFont {
        return systemFont(ofSize: size)
    }
    
    public class func boldSystemFont(size: CGFloat) -> OKFont {
        return boldSystemFont(ofSize: size)
    }
}

extension OKColor {
    
    //MARK: - Hex
    
    public convenience init(hexRGB: Int, alpha: CGFloat = 1.0) {
        
        self.init(red:CGFloat((hexRGB >> 16) & 0xff) / 255.0,
                  green:CGFloat((hexRGB >> 8) & 0xff) / 255.0,
                  blue:CGFloat(hexRGB & 0xff) / 255.0,
                  alpha: alpha)
    }
    
    public class func randomColor() -> OKColor {
        
        return OKColor(red: CGFloat(arc4random_uniform(255)) / 255.0,
                       green: CGFloat(arc4random_uniform(255)) / 255.0,
                       blue: CGFloat(arc4random_uniform(255)) / 255.0,
                       alpha: 1.0)
        
    }
}

class OKView: UIView {
    
    public var okBackgroundColor: OKColor? {
        didSet {
            backgroundColor = okBackgroundColor
        }
    }
    
    public func okSetNeedsDisplay() {
        setNeedsDisplay()
    }
    
    public func okSetNeedsDisplay(_ rect: CGRect) {
        setNeedsDisplay(rect)
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        super.draw(rect)
    }
}

class OKScrollView: UIScrollView {

}

class OKButton: UIButton {
    
}

public func OKPrint(_ object: @autoclosure() -> Any?,
                    _ file: String = #file,
                    _ function: String = #function,
                    _ line: Int = #line) {
    #if DEBUG
        guard let value = object() else {
            return
        }
        var stringRepresentation: String?
        
        if let value = value as? CustomDebugStringConvertible {
            stringRepresentation = value.debugDescription
        }
        else if let value = value as? CustomStringConvertible {
            stringRepresentation = value.description
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss:SSS"
        let timestamp = formatter.string(from: Date())
        let queue = Thread.isMainThread ? "UI" : "BG"
        let fileURL = NSURL(string: file)?.lastPathComponent ?? "Unknown file"
        
        if let string = stringRepresentation {
            print("✅ \(timestamp) {\(queue)} \(fileURL) > \(function)[\(line)]: \(string)")
        } else {
            print("✅ \(timestamp) {\(queue)} \(fileURL) > \(function)[\(line)]: \(value)")
        }
    #endif
}

protocol OKDescriptable {
    func propertyDescription() -> String
}

extension OKDescriptable {
    func propertyDescription() -> String {
        let strings = Mirror(reflecting: self).children.flatMap { "\($0.label!): \($0.value)" }
        var string = ""
        for str in strings {
            string += String(str) + "\n"
        }
        return string
    }
}

// fix frame bound compare by CC on 2018/2/7
extension CGRect {
    public static func isSame(_ rect1 : CGRect, _ rect2 : CGRect) -> Bool {
        let min : Double = 0.000001
        var delta1 : CGFloat = rect1.origin.x - rect2.origin.x
        var delta2 : CGFloat = rect1.origin.y - rect2.origin.y
        var delta3 : CGFloat = rect1.size.width - rect2.size.width
        var delta4 : CGFloat = rect1.size.height - rect2.size.height
        
        if delta1 != 0 {
            if fabs(Double(delta1)) < min {
                delta1 = 0
            }
        }
        
        if delta2 != 0 {
            if fabs(Double(delta1)) < min {
                delta2 = 0
            }
        }
        
        if delta3 != 0 {
            if fabs(Double(delta1)) < min {
                delta3 = 0
            }
        }
        
        if delta4 != 0 {
            if fabs(Double(delta4)) < min {
                delta4 = 0
            }
        }
        
        return (delta1 == 0) && (delta2 == 0) && (delta3 == 0) && (delta4 == 0)
    }
}

extension CGContext {
    public func setWidthWithRound (_ width: CGFloat) {
        var useWidth : CGFloat = 0.5
        if width <= 0.001 || width > 100 {
            useWidth = 1;
        } else {
            useWidth = width;
        }
        
        setLineWidth(useWidth)
        setLineCap(.round)
        setLineJoin(.round)
    }
}



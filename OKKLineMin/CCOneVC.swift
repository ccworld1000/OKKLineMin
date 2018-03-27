//
//  CCOneVC.swift
//  OKKLineMin
//
//  Created by dengyouhua on 22/03/2018.
//  Copyright © 2018 cc | ccworld1000@gmail.com. All rights reserved.
//  https://github.com/ccworld1000/OKKLineMin
//

import UIKit

class CCOneVC: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }
    
    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
        
        if  segue.destination != nil {
            let vc : CCKlineVC = segue.destination as! CCKlineVC
            if let vcString = segue.identifier {
                if vcString == "one" {
                    vc.isFull = true;
                }
            }
        }
    }
}

//
//  CCTwoVC.swift
//  OKKLineMin
//
//  Created by dengyouhua on 22/03/2018.
//  Copyright © 2018 cc | ccworld1000@gmail.com. All rights reserved.
//  https://github.com/ccworld1000/OKKLineMin
//

import UIKit

class CCTwoVC: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if  let vc : CCKlineVC = segue.destination as? CCKlineVC {
            if let vcString = segue.identifier {
                if vcString == "FULL" {
                    vc.isFull = true;
                }
            }
        }
    }
}

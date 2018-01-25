//
//  OKKLineMinVC.swift
//  OKKLineMin
//
//  Created by dengyouhua on 25/01/2018.
//  Copyright © 2018 cc | ccworld1000@gmail.com. All rights reserved.
//

import UIKit

class OKKLineMinVC: UIViewController {

    @IBOutlet weak var backgroundView: UIView!
    let iphonexOffset : CGFloat = 30;
    var klineView: OKKLineView!
    
    
    var backButton: UIButton!;
    func loadingUI() {
        print(loadingUI)
        
        backButton = UIButton(type: .custom)
        backButton.setTitle("Back", for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(size: 12)
        backButton.backgroundColor = UIColor.blue
        backButton.addTarget(self, action:#selector(backHandle(button:)) , for: .touchUpInside)
        
        backgroundView.addSubview(backButton)
        backButton.snp.makeConstraints { (make) in
            make.top.equalToSuperview()
            make.left.equalToSuperview()
            make.size.equalTo(CGSize(width: 50, height: 20))
        }
    }
    
    @objc func backHandle(button: UIButton) {
        print("backHandle")
        dismiss(animated: true, completion: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = OKConfiguration.sharedConfiguration.main.backgroundColor
        klineView = OKKLineView()
        klineView.doubleTapHandle = { () -> Void in
            self.dismiss(animated: true, completion: nil)
        }

        backgroundView.addSubview(self.klineView)
        
        klineView.snp.makeConstraints { (make) in
            make.edges.equalToSuperview()
        }
        
        loadingUI()

        sqliteHandle()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        UIApplication.shared.isStatusBarHidden = true
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        UIApplication.shared.isStatusBarHidden = false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .landscape
    }
    
    func sqliteHandle() {
        print(sqliteHandle)
        
        if let list = CCSQLiteData.readDefaultDataList() {
            let datas = list as! [[Double]]
            
            print(datas.count)
            var dataArray = [OKKLineModel]()
            for data in datas {
                let model = OKKLineModel(date: data[0], open: data[1], close: data[4], high: data[2], low: data[3], volume: data[5])
                dataArray.append(model)
            }
            
            self.klineView.drawKLineView(klineModels: dataArray)
        }
    }
}

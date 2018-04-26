//
//  CCHalfVC.swift
//  OKKLineMin
//
//  Created by dengyouhua on 21/03/2018.
//  Copyright © 2018 cc | ccworld1000@gmail.com. All rights reserved.
//  https://github.com/ccworld1000/OKKLineMin
//

import UIKit

class CCKlineVC: UIViewController {

    @IBOutlet weak var backgroundView: UIView!
    var klineView: OKKLineView!
    var backButton: UIButton!
    
    var isFull : Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
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
        if isFull {
            return .landscape
        } else {
            return .portrait
        }
    }
    
    @objc func backHandle(button: UIButton) {
        dismiss(animated: true, completion: nil)
    }
    
    func loadingUI() {
        self.view.backgroundColor = OKConfiguration.sharedConfiguration.main.backgroundColor
        klineView = OKKLineView()
        backgroundView.addSubview(self.klineView)
        
        if isFull {
            klineView.snp.makeConstraints { (make) in
                make.edges.equalToSuperview()
            }
        } else {
            klineView.snp.makeConstraints { (make) in
                make.left.equalToSuperview();
                make.top.equalToSuperview().offset(0.001);
                make.right.equalToSuperview();
                make.height.equalTo(backgroundView.bounds.size.height / 2.0 )
            }
        }

        
        backButton = UIButton(type: .custom)
        backButton.setTitle("Back", for: .normal)
        backButton.titleLabel?.font = UIFont.systemFont(size: 12)
        backButton.backgroundColor = UIColor.blue
        backButton.addTarget(self, action:#selector(backHandle(button:)) , for: .touchUpInside)
        
        self.backgroundView.addSubview(backButton)
        backButton.snp.makeConstraints { (make) in
            make.top.equalToSuperview()
            make.left.equalToSuperview()
            make.size.equalTo(CGSize(width: 50, height: 20))
        }
    }
    
    func sqliteHandle() {
        if let list = CCSQLiteData.readDefaultDataList() {
            let datas = list as! [[Double]]
            
            var dataArray = [OKKLineModel]()
            for data in datas {
                let model = OKKLineModel(date: data[0], open: data[1], close: data[4], high: data[2], low: data[3], volume: data[5])
                dataArray.append(model)
            }
            
            self.klineView.drawKLineView(klineModels: dataArray)
        }
    }
}



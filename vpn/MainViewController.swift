//
//  MainViewController.swift
//  vpn
//
//  Created by fengfeng on 2017/12/4.
//  Copyright © 2017年 fengfeng. All rights reserved.
//

import UIKit
import NetworkExtension

let count = 1

class MainViewController: UIViewController,GCDAsyncSocketDelegate {

    @IBOutlet weak var connect: UIButton!
    @IBOutlet weak var content: LTMorphingLabel!
    
    var clientSocket: GCDAsyncSocket!
    var nowTime = TimeInterval()
    var models = [FFSSModel]()
    var maxErrCount = count
    var maxCount = count
    var startTime:Int = 0
    var index = 0
    
    var status: VPNStatus {
        didSet(o) {
            updateConnectButton()
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        self.status = .off
        super.init(coder: aDecoder)
        NotificationCenter.default.addObserver(self, selector: #selector(onVPNStatusChanged), name: kProxyServiceVPNStatusNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: kProxyServiceVPNStatusNotification, object: nil)
    }
    
    @objc func onVPNStatusChanged(){
        self.status = VpnManager.shared.vpnStatus
    }
    
    func updateConnectButton(){
        switch status {
        case .connecting:
            content.text = NSLocalizedString("connect.ing", comment: "")
        case .disconnecting:
            content.text = NSLocalizedString("connect.dis", comment: "")
        case .on:
            connect.setTitle(NSLocalizedString("disconnect", comment: ""), for: .normal)
            content.text = NSLocalizedString("connect.on", comment: "")
            self.connect.startPulse(with: .white, animation: .radarPulsing)
        case .off:
            connect.setTitle(NSLocalizedString("connect", comment: ""), for: .normal)
            content.text = NSLocalizedString("connect.off", comment: "")
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            if(VpnManager.shared.vpnStatus == .on){
                self.connect.startPulse(with: .white, animation: .radarPulsing)
            }else{
                self.connect.stopPulse()
            }
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        connect.titleLabel?.adjustsFontSizeToFitWidth = true
        UIApplication.shared.statusBarStyle = .lightContent
        content.morphingEffect = .evaporate
        loadData()
    }
    
    @IBAction func clickConnect(_ sender: UIButton) {
        self.connect.isUserInteractionEnabled = false
        if sender.titleLabel?.text==NSLocalizedString("connect",comment: "") {
            self.content.text = NSLocalizedString("connect.ing", comment: "")
        }else{
            self.content.text = NSLocalizedString("connect.dis", comment: "")
        }
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            if(VpnManager.shared.vpnStatus == .off){
                self.ping(index: 0)
            }else{
                self.connect.stopPulse()
                self.connect.isUserInteractionEnabled = true
                VpnManager.shared.disconnect()
            }
        }
    }
    
    // 获取你的服务器ip地址和密码和端口
    func loadData(){
        let model = FFSSModel()
        model.ip = "127.0.0.1"
        model.pwd = "wobugaosuni"
        model.port = 233
        self.models.append(model)
    }
    
    // 链接之前ping下地址是否可用
    func ping(index:Int) {
        if index==models.count {
            connect.setTitle(NSLocalizedString("connect", comment: ""), for: .normal)
            content.text = NSLocalizedString("connect.false", comment: "")
            connect.isUserInteractionEnabled = true
            self.index = 0
            return
        }
        let model = models[index]
        maxCount = count
        maxErrCount = count
        clientSocket = GCDAsyncSocket.init(socketQueue: DispatchQueue.main)
        clientSocket.delegate = self
        clientSocket.delegateQueue = DispatchQueue.main
        try! clientSocket.connect(toHost: model.ip, onPort: UInt16(model.port), withTimeout: 3)
        startTime = LDNetTimer.getMicroSeconds()
    }
    
    func socket(_ sock: GCDAsyncSocket, didConnectToHost host: String, port: UInt16) {
        let interval = LDNetTimer.computeDuration(since: startTime) / 1000
        let time = String.init(describing: interval)+" ms"
        clientSocket.disconnect()
        self.content.text = String.init(format: NSLocalizedString("connect.ping", comment: ""),time)
        
        let model = models[index]
        if maxCount != 0 {
            maxCount -= 1
            DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                try! self.clientSocket.connect(toHost: model.ip, onPort: UInt16(model.port), withTimeout: 3)
                self.startTime = LDNetTimer.getMicroSeconds()
            }
        }else{
            DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                VpnManager.shared.ip = model.ip
                VpnManager.shared.pwd = model.pwd
                VpnManager.shared.port = model.port
                VpnManager.shared.connect()
                self.connect.isUserInteractionEnabled = true
            }
        }
    }
    
    // 如果ping几次后ip不能用,就切换到另一个ip继续ping,直到所有ip都不能用才显示没有ip可用
    func socketDidDisconnect(_ sock: GCDAsyncSocket, withError err: Error?) {
        if err != nil {
            print(err!.localizedDescription)
            self.content.text = String.init(format: NSLocalizedString("connect.ping", comment: ""), "timeout")
            if maxErrCount==0 {
                let model = models[index]
                DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                    try! self.clientSocket.connect(toHost: model.ip, onPort: UInt16(model.port), withTimeout: 3)
                    self.startTime = LDNetTimer.getMicroSeconds()
                }
                return
            }
            maxErrCount -= 1
            self.content.text = NSLocalizedString("connect.change", comment: "")
            DispatchQueue.main.asyncAfter(deadline: .now()+1, execute: {
                self.index += 1
                self.ping(index: self.index)
            })
        }
    }
    
    // 开始连接服务器
    func connectDidTime(_ time: String!) {
        self.content.text = String.init(format: NSLocalizedString("connect.ping", comment: ""),time)
        let model = models[index]
        DispatchQueue.main.asyncAfter(deadline: .now()+1) {
            VpnManager.shared.ip = model.ip
            VpnManager.shared.pwd = model.pwd
            VpnManager.shared.port = model.port
            VpnManager.shared.connect()
            self.connect.isUserInteractionEnabled = true
        }
    }
}

//
//  VpnManager.swift
//  rabbit
//
//  Created by CYC on 2016/11/19.
//  Copyright © 2016年 yicheng. All rights reserved.
//

import Foundation
import NetworkExtension
import Yaml

let kProxyServiceVPNStatusNotification = NSNotification.Name(rawValue: "kProxyServiceVPNStatusNotification")

enum VPNStatus {
    case off
    case connecting
    case on
    case disconnecting
}


class VpnManager{
    static let shared = VpnManager()
    var observerAdded: Bool = false
    var ip = String()
    var pwd = String()
    var port = NSInteger()

    fileprivate(set) var vpnStatus = VPNStatus.off {
        didSet {
            NotificationCenter.default.post(name: kProxyServiceVPNStatusNotification, object: nil)
        }
    }
    
    init() {
        loadProviderManager{
            guard let manager = $0 else{return}
            self.updateVPNStatus(manager)
        }
        addVPNStatusObserver()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func addVPNStatusObserver() {
        loadProviderManager { [unowned self] (manager) -> Void in
            if let manager = manager {
                self.observerAdded = true
                NotificationCenter.default.addObserver(forName: NSNotification.Name.NEVPNStatusDidChange, object: manager.connection, queue: OperationQueue.main, using: { [unowned self] (notification) -> Void in
                    self.updateVPNStatus(manager)
                })
            }
        }
    }
    
    func updateVPNStatus(_ manager: NEVPNManager) {
        switch manager.connection.status {
        case .connected:
            self.vpnStatus = .on
        case .connecting, .reasserting:
            self.vpnStatus = .connecting
        case .disconnecting:
            self.vpnStatus = .disconnecting
        case .disconnected, .invalid:
            self.vpnStatus = .off
        }
        print(self.vpnStatus)
    }
}

// load VPN Profiles
extension VpnManager{

    fileprivate func createProviderManager() -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let conf = NETunnelProviderProtocol()
        conf.serverAddress = "SS-VPN"
        manager.protocolConfiguration = conf
        manager.localizedDescription = "SS"
        return manager
    }
    
    
    func loadAndCreatePrividerManager(_ complete: @escaping (NETunnelProviderManager?) -> Void ){
        NETunnelProviderManager.loadAllFromPreferences{ (managers, error) in
            guard let managers = managers else{return}
            let manager: NETunnelProviderManager
            if managers.count > 0 {
                manager = managers[0]
                self.delDupConfig(managers)
            }else{
                manager = self.createProviderManager()
            }
            
            manager.isEnabled = true
            self.setRulerConfig(manager)
            manager.saveToPreferences(completionHandler: { (error) in
                if error != nil{complete(nil);return;}
                manager.loadFromPreferences(completionHandler: { (error) in
                    if error != nil{
                        print(error.debugDescription)
                        complete(nil);return;
                    }
                    self.addVPNStatusObserver()
                    complete(manager)
                })
            })
        }
    }
    
    func loadProviderManager(_ complete: @escaping (NETunnelProviderManager?) -> Void){
        NETunnelProviderManager.loadAllFromPreferences { (managers, error) in
            if let managers = managers {
                if managers.count > 0 {
                    let manager = managers.first!
                    complete(manager)
                    return
                }
            }
            complete(nil)
        }
    }
    
    func delDupConfig(_ arrays:[NETunnelProviderManager]){
        if (arrays.count)>1{
            for i in 0 ..< arrays.count{
                print("删除 DUP 配置文件")
                arrays[i].removeFromPreferences(completionHandler: { (error) in
                    if(error != nil){print(error.debugDescription)}
                })
            }
        }
    }
}

// Actions
extension VpnManager{
    func connect(){
        self.loadAndCreatePrividerManager { (manager) in
            guard let manager = manager else{return}
            do{
                let userDefault = UserDefaults.init(suiteName: "group.com.cff")!
                userDefault.set(true, forKey: "isapp")
                try manager.connection.startVPNTunnel()
            }catch let err{
                print(err)
            }
        }
    }
    
    func disconnect(){
        loadProviderManager { (manager) in
            if manager != nil {
                manager?.connection.stopVPNTunnel()
            }
        }
    }
}

// Generate and Load ConfigFile
extension VpnManager{
    fileprivate func getRuleConf() -> String{
        let Path = Bundle.main.path(forResource: "rules", ofType: "json")
        let Data = try? Foundation.Data(contentsOf: URL(fileURLWithPath: Path!))
        let str = String(data: Data!, encoding: String.Encoding.utf8)!
        return str
    }
    
    fileprivate func setRulerConfig(_ manager:NETunnelProviderManager){
        NSLog("配置 conf")
        var conf = [String:AnyObject]()
        conf["ss_address"] = ip as AnyObject
        conf["ss_port"] = port as AnyObject
        conf["ss_method"] = "CHACHA20" as AnyObject?
        conf["ss_password"] = pwd as AnyObject?
        conf["json_conf"] = getRuleConf() as AnyObject?
        conf["isapp"] = true as AnyObject
        
        let orignConf = manager.protocolConfiguration as! NETunnelProviderProtocol
        orignConf.providerConfiguration = conf
        manager.protocolConfiguration = orignConf
        ip = ""
        port = 0
        pwd = ""
    }
}

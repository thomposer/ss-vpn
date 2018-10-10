//
//  PacketTunnelProvider.swift
//  PacketTunnel
//
//  Created by fengfeng on 2017/10/27.
//Copyright © 2017年 fengfeng. All rights reserved.
//

import NetworkExtension
import CocoaLumberjackSwift
import NEKit
import Yaml
import SwiftyJSON

class PacketTunnelProvider: NEPacketTunnelProvider {
    
    var interface: TUNInterface!
    var enablePacketProcessing = false
    var proxyPort: Int!
    var proxyServer: ProxyServer!
    var lastPath:NWPath?
    var started:Bool = false

    override func startTunnel(options: [String : NSObject]?, completionHandler: @escaping (Error?) -> Void) {
        DDLog.removeAllLoggers()
        DDLog.add(DDASLLogger.sharedInstance, with: DDLogLevel.info)
        ObserverFactory.currentFactory = DebugObserverFactory()
        NSLog("开始连接---------------------------------------")
        
        guard var conf = (protocolConfiguration as! NETunnelProviderProtocol).providerConfiguration else{
            NSLog("[错误]找不到协议配置")
            exit(EXIT_FAILURE)
        }
        let userDefault = UserDefaults.init(suiteName: "group.com.cff")!
        NSLog(userDefault.string(forKey: "isapp")!)
        if !userDefault.bool(forKey: "isapp") {
            NSLog("[错误]不是从 APP 打开")
            proxyServer.stop()
            exit(EXIT_FAILURE)
        }
        
        let ss_adder = conf["ss_address"] as! String
        NSLog("ip:"+ss_adder)
        
        let ss_port = conf["ss_port"] as! Int
        NSLog("端口:"+"\(ss_port)")
        
        let method = conf["ss_method"] as! String
        NSLog("加密:"+method)

        let password = conf["ss_password"] as!String
        
        NETunnelProviderProtocol().providerConfiguration = [String:Any]()
        
        
        let obfuscater = ShadowsocksAdapter.ProtocolObfuscater.OriginProtocolObfuscater.Factory()
        
        let algorithm:CryptoAlgorithm
        
        switch method{
        case "AES128CFB":algorithm = .AES128CFB
        case "AES192CFB":algorithm = .AES192CFB
        case "AES256CFB":algorithm = .AES256CFB
        case "CHACHA20":algorithm = .CHACHA20
        case "SALSA20":algorithm = .SALSA20
        case "RC4MD5":algorithm = .RC4MD5
        default:
            fatalError("未定义的算法！")
        }
        
        let ssAdapterFactory = ShadowsocksAdapterFactory(serverHost: ss_adder, serverPort: ss_port, protocolObfuscaterFactory:obfuscater, cryptorFactory: ShadowsocksAdapter.CryptoStreamProcessor.Factory(password: password, algorithm: algorithm), streamObfuscaterFactory: ShadowsocksAdapter.StreamObfuscater.OriginStreamObfuscater.Factory())
        
        let directAdapterFactory = DirectAdapterFactory()
        
        //Get lists from conf
        let json_str = conf["json_conf"] as! String
        let json = JSON.init(parseJSON: json_str)
        NSLog("json解析")
        var UserRules:[NEKit.Rule] = []
        var adapter:NEKit.AdapterFactory
        adapter = directAdapterFactory
        let arraydom = json["rules"]["DOMAIN"].arrayValue
        let arrayip = json["rules"]["IP"].arrayValue
        let dom_direct = getDomRule(list: arraydom, isDirect: true)
        UserRules.append(DomainListRule(adapterFactory: adapter, criteria: dom_direct))
        let ip_direct = getIPRule(list: arrayip, isDirect: true)
        var ipdirect:NEKit.Rule!
        do {
            ipdirect = try IPRangeListRule(adapterFactory: adapter, ranges: ip_direct)
        }catch let error as NSError {
            NSLog("ip解析:"+error.domain)
        }
        UserRules.append(ipdirect)
        
        adapter = ssAdapterFactory
        let dom_proxy = getDomRule(list: arraydom, isDirect: false)
        UserRules.append(DomainListRule(adapterFactory: adapter, criteria: dom_proxy))
        let ip_proxy = getIPRule(list: arrayip, isDirect: false)
        
        var iprule:NEKit.Rule!
        do {
            iprule = try IPRangeListRule(adapterFactory: adapter, ranges: ip_proxy)
        }catch let error as NSError {
            NSLog("ip解析:"+error.domain)
        }
        UserRules.append(iprule)
        
        
        // Rules
        let chinaRule = CountryRule(countryCode: "CN", match: true, adapterFactory: directAdapterFactory)
        let unKnowLoc = CountryRule(countryCode: "--", match: true, adapterFactory: directAdapterFactory)
        let dnsFailRule = DNSFailRule(adapterFactory: ssAdapterFactory)
     
        let allRule = AllRule(adapterFactory: ssAdapterFactory)
        UserRules.append(contentsOf: [chinaRule,unKnowLoc,dnsFailRule,allRule])
        
        let manager = RuleManager(fromRules: UserRules, appendDirect: true)
        
        RuleManager.currentManager = manager
        proxyPort =  9090
        
        // the `tunnelRemoteAddress` is meaningless because we are not creating a tunnel.
        let networkSettings = NEPacketTunnelNetworkSettings(tunnelRemoteAddress: "8.8.8.8")
        networkSettings.mtu = 1500
        
        let ipv4Settings = NEIPv4Settings(addresses: ["192.169.89.1"], subnetMasks: ["255.255.255.0"])
        if enablePacketProcessing {
            ipv4Settings.includedRoutes = [NEIPv4Route.default()]
            ipv4Settings.excludedRoutes = [
                NEIPv4Route(destinationAddress: "10.0.0.0", subnetMask: "255.0.0.0"),
                NEIPv4Route(destinationAddress: "100.64.0.0", subnetMask: "255.192.0.0"),
                NEIPv4Route(destinationAddress: "127.0.0.0", subnetMask: "255.0.0.0"),
                NEIPv4Route(destinationAddress: "169.254.0.0", subnetMask: "255.255.0.0"),
                NEIPv4Route(destinationAddress: "172.16.0.0", subnetMask: "255.240.0.0"),
                NEIPv4Route(destinationAddress: "192.168.0.0", subnetMask: "255.255.0.0"),
                NEIPv4Route(destinationAddress: "17.0.0.0", subnetMask: "255.0.0.0"),
            ]
        }
        networkSettings.ipv4Settings = ipv4Settings
        
        let proxySettings = NEProxySettings()
        proxySettings.httpEnabled = true
        proxySettings.httpServer = NEProxyServer(address: "127.0.0.1", port: proxyPort)
        proxySettings.httpsEnabled = true
        proxySettings.httpsServer = NEProxyServer(address: "127.0.0.1", port: proxyPort)
        proxySettings.excludeSimpleHostnames = true
        // This will match all domains
        proxySettings.matchDomains = [""]
        proxySettings.exceptionList = ["api.smoot.apple.com","configuration.apple.com","xp.apple.com","smp-device-content.apple.com","guzzoni.apple.com","captive.apple.com","*.ess.apple.com","*.push.apple.com","*.push-apple.com.akadns.net"]
        networkSettings.proxySettings = proxySettings
        
        if enablePacketProcessing {
            let DNSSettings = NEDNSSettings(servers: ["198.18.0.1"])
            DNSSettings.matchDomains = [""]
            DNSSettings.matchDomainsNoSearch = false
            networkSettings.dnsSettings = DNSSettings
        }
        
        setTunnelNetworkSettings(networkSettings) {
            error in
            guard error == nil else {
                DDLogError("Encountered an error setting up the network: \(error.debugDescription)")
                completionHandler(error)
                return
            }
            
            if !self.started{
                self.proxyServer = GCDHTTPProxyServer(address: IPAddress(fromString: "127.0.0.1"), port: NEKit.Port(port: UInt16(self.proxyPort)))
                try! self.proxyServer.start()
                self.addObserver(self, forKeyPath: "defaultPath", options: .initial, context: nil)
            }else{
                self.proxyServer.stop()
                try! self.proxyServer.start()
            }
            completionHandler(nil)
            
            if self.enablePacketProcessing {
                if self.started{
                    self.interface.stop()
                }
                self.interface = TUNInterface(packetFlow: self.packetFlow)
                
                let fakeIPPool = try! IPPool(range: IPRange(startIP: IPAddress(fromString: "198.18.1.1")!, endIP: IPAddress(fromString: "198.18.255.255")!))
                
                let dnsServer = DNSServer(address: IPAddress(fromString: "198.18.0.1")!, port: NEKit.Port(port: 53), fakeIPPool: fakeIPPool)
                let resolver = UDPDNSResolver(address: IPAddress(fromString: "114.114.114.114")!, port: NEKit.Port(port: 53))
                dnsServer.registerResolver(resolver)
                self.interface.register(stack: dnsServer)
                
                DNSServer.currentServer = dnsServer
                
                let udpStack = UDPDirectStack()
                self.interface.register(stack: udpStack)
                let tcpStack = TCPStack.stack
                tcpStack.proxyServer = self.proxyServer
                self.interface.register(stack:tcpStack)
                self.interface.start()
            }
            self.started = true
        }
    }
    
    func getDomRule(list:[JSON],isDirect:Bool) -> [NEKit.DomainListRule.MatchCriterion] {
        var rule_dom : [NEKit.DomainListRule.MatchCriterion] = []
        for item in list {
            let str = item.stringValue.replacingOccurrences(of: " ", with: "")
            let components = str.components(separatedBy: ",")
            let type = components[0]
            let value = components[1]
            let adap = components[2]
            if isDirect {
                if type=="DOMAIN-SUFFIX" && adap=="DIRECT" {
                    rule_dom.append(DomainListRule.MatchCriterion.suffix(value))
                }
                if type=="DOMAIN-KEYWORD" && adap=="DIRECT" {
                    rule_dom.append(DomainListRule.MatchCriterion.suffix(value))
                }
            }else{
                if type=="DOMAIN-SUFFIX" && adap=="PROXY" {
                    rule_dom.append(DomainListRule.MatchCriterion.suffix(value))
                }
                if type=="DOMAIN-KEYWORD" && adap=="PROXY" {
                    rule_dom.append(DomainListRule.MatchCriterion.suffix(value))
                }
            }
        }
        return rule_dom
    }
    
    func getIPRule(list:[JSON],isDirect:Bool) -> [String] {
        var rule_ip : [String] = []
        for item in list {
            let str = item.stringValue.replacingOccurrences(of: " ", with: "")
            let components = str.components(separatedBy: ",")
//            let type = components[0]
            let value = components[1]
            let adap = components[2]
            if isDirect {
                if adap=="DIRECT" {
                    rule_ip.append(value)
                }
            }else{
                if adap=="PROXY" {
                    rule_ip.append(value)
                }
            }
        }
        return rule_ip
    }
    

    override func stopTunnel(with reason: NEProviderStopReason, completionHandler: @escaping () -> Void) {
        if enablePacketProcessing {
            interface.stop()
            interface = nil
            DNSServer.currentServer = nil
        }
        if(proxyServer != nil){
            proxyServer.stop()
            proxyServer = nil
            RawSocketFactory.TunnelProvider = nil
        }
        let userDefault = UserDefaults.init(suiteName: "group.com.cff")!
        userDefault.set(false, forKey: "isapp")
        completionHandler()
        NSLog("停止 vpn")
        NSLog(userDefault.string(forKey: "isapp")!)
        exit(EXIT_SUCCESS)
    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "defaultPath" {
            if self.defaultPath?.status == .satisfied{
                if(lastPath == nil){
                    NSLog("lastPath == nil")
                    lastPath = self.defaultPath
                }
                NSLog("收到网络变更通知")
                DispatchQueue.main.asyncAfter(deadline: .now()+1) {
                    self.startTunnel(options: nil){_ in}
                }
            }else{
                NSLog("lastPath = defaultPath")
                lastPath = defaultPath
            }
        }
    }

}



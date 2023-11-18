#if canImport(Flutter)
    import Flutter
#endif
#if canImport(FlutterMacOS)
    import FlutterMacOS
#endif
import Network

/// Allows to broadcast a given service to the local network.
@available(iOS 13.0, macOS 10.15, *)
class BonsoirServiceBroadcast: NSObject, FlutterStreamHandler {
    /// The delegate identifier.
    let id: Int

    /// Whether to print debug logs.
    let printLogs: Bool

    /// Triggered when this instance is being disposed.
    let onDispose: () -> Void
    
    /// The advertised service.
    let service: BonsoirService
    
    /// The reference to the registering..
    var sdRef: DNSServiceRef?
    
    /// The current event channel.
    var eventChannel: FlutterEventChannel?

    /// The current event sink.
    var eventSink: FlutterEventSink?

    /// Initializes this class.
    public init(id: Int, printLogs: Bool, onDispose: @escaping () -> Void, messenger: FlutterBinaryMessenger, service: BonsoirService) {
        self.id = id
        self.printLogs = printLogs
        self.onDispose = onDispose
        self.service = service
        super.init()
        eventChannel = FlutterEventChannel(name: "\(SwiftBonsoirPlugin.package).broadcast.\(id)", binaryMessenger: messenger)
        eventChannel?.setStreamHandler(self)
    }
    
    func onListen(withArguments arguments: Any?, eventSink: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = eventSink
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
    
    /// Starts the broadcast.
    public func start() {
        var txtRecord: TXTRecordRef = TXTRecordRef();
        TXTRecordCreate(&txt_record, 0, nil);
        for (key, value) in service.attributes! {
          TXTRecordSetValue(&txtRecord, key, UInt8(value.count), value)
        }
        let error = DNSServiceRegister(&sdRef, 0, 0, service.name, service.type, "local.", service.host, CFSwapInt16HostToBig(UInt16(service.port)), TXTRecordGetLength(&txt_record), TXTRecordGetBytesPtr(&txt_record), { sdRef, flags, errorCode, name, regType, domain, context in
            let broadcast = Unmanaged<BonsoirServiceBroadcast>.fromOpaque(context!).takeUnretainedValue()
            if errorCode == kDNSServiceErr_NoError {
                if broadcast.service.name != name {
                    let oldName = broadcast.service.name
                    broadcast.service.name = name
                    if broadcast.printLogs {
                        SwiftBonsoirPlugin.log(category: "broadcast", id: broadcast.id, message: "Trying to broadcast a service with a name that already exists : \(broadcast.service.description) (old name was \(oldName))")
                    }
                    broadcast.eventSink?(SuccessObject(id: "broadcastNameAlreadyExists", service: broadcast.service).toJson())
                }
                if broadcast.printLogs {
                    SwiftBonsoirPlugin.log(category: "broadcast", id: broadcast.id, message: "Bonsoir service broadcasted : \(broadcast.service.description)")
                }
                broadcast.eventSink?(SuccessObject(id: "broadcastStarted", service: broadcast.service).toJson())
            }
            else {
                if broadcast.printLogs {
                    SwiftBonsoirPlugin.log(category: "broadcast", id: broadcast.id, message: "Bonsoir service failed to broadcast : \(broadcast.service.description), error code : \(errorCode)")
                }
                broadcast.eventSink?(FlutterError.init(code: "broadcastError", message: "Bonsoir service failed to broadcast.", details: errorCode))
                broadcast.dispose()
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        if error == kDNSServiceErr_NoError {
            if printLogs {
                SwiftBonsoirPlugin.log(category: "broadcast", id: id, message: "Bonsoir service broadcast initialized : \(service.description)")
            }
            DNSServiceProcessResult(sdRef)
        } else {
            if printLogs {
                SwiftBonsoirPlugin.log(category: "broadcast", id: id, message: "Bonsoir service failed to broadcast : \(service.description), error code : \(error)")
            }
            eventSink?(FlutterError.init(code: "broadcastError", message: "Bonsoir service failed to broadcast.", details: error))
            dispose()
        }
    }

    /// Disposes the current class instance.
    public func dispose() {
        DNSServiceRefDeallocate(sdRef)
        if printLogs {
            SwiftBonsoirPlugin.log(category: "broadcast", id: id, message: "Bonsoir service broadcast stopped : \(service.description)")
        }
        eventSink?(SuccessObject(id: "broadcastStopped", service: service).toJson())
        onDispose()
    }
}
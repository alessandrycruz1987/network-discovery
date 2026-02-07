import Foundation

@objc public class NetworkDiscovery: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}

import Darwin
import Foundation

struct LocalNetworkInterface: Equatable, Sendable {
    let name: String
    let address: String
    let isIPv6: Bool
}

enum LocalNetworkAddress {
    static let ignoredPrefixes = ["lo", "utun", "awdl", "llw", "gif", "stf", "anpi", "ap"]

    static func interfaces() -> [LocalNetworkInterface] {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return [] }
        defer { freeifaddrs(pointer) }
        var result: [LocalNetworkInterface] = []
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_RUNNING != 0, flags & IFF_LOOPBACK == 0,
                  let socketAddress = entry.pointee.ifa_addr
            else { continue }
            let family = Int32(socketAddress.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(family == AF_INET ? MemoryLayout<sockaddr_in>.size : MemoryLayout<sockaddr_in6>.size)
            guard getnameinfo(socketAddress, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let address = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            result.append(LocalNetworkInterface(name: String(cString: entry.pointee.ifa_name), address: address, isIPv6: family == AF_INET6))
        }
        return result
    }

    static func candidates(from interfaces: [LocalNetworkInterface]) -> [LocalNetworkInterface] {
        interfaces
            .filter { interface in
                !ignoredPrefixes.contains { interface.name.hasPrefix($0) } && isShareable(interface)
            }
            .enumerated()
            .sorted { lhs, rhs in
                let left = rank(lhs.element)
                let right = rank(rhs.element)
                return left != right ? left < right : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    static func rank(_ interface: LocalNetworkInterface) -> Int {
        let family = interface.isIPv6 ? 10 : 0
        if interface.name == "en0" { return family }
        if interface.name.hasPrefix("en") { return family + 1 }
        if interface.name.hasPrefix("bridge") { return family + 2 }
        return family + 3
    }

    static func isShareable(_ interface: LocalNetworkInterface) -> Bool {
        if interface.isIPv6 {
            let lowered = interface.address.lowercased()
            return !lowered.hasPrefix("fe80") && !lowered.contains("%")
        }
        return !interface.address.hasPrefix("169.254.") && !interface.address.hasPrefix("127.")
    }

    static func urlHost(for interface: LocalNetworkInterface) -> String {
        interface.isIPv6 ? "[\(interface.address)]" : interface.address
    }

    static func isPrivateHost(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else {
            let lowered = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            return lowered == "localhost" || lowered.hasPrefix("fd") || lowered.hasPrefix("fc") || lowered.hasPrefix("fe80") || lowered.hasSuffix(".local")
        }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168), (169, 254): return true
        case let (172, second): return (16 ... 31).contains(second)
        case let (100, second): return (64 ... 127).contains(second)
        default: return false
        }
    }

    static func urls(port: UInt16, path: String, interfaces: [LocalNetworkInterface] = interfaces()) -> [URL] {
        candidates(from: interfaces).compactMap { interface in
            URL(string: "http://\(urlHost(for: interface)):\(port)\(path)")
        }
    }
}

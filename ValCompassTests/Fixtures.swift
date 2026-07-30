import Foundation
@testable import ValCompass

/// 离线 fixture 加载
enum Fixtures {
    enum FixtureError: Error, Equatable {
        case missing(String)
    }

    /// 按名字加载 fixture。Xcode 通常把资源拷到测试 bundle 根目录；
    /// 若 XcodeGen 保留了 Fixtures 目录结构，则在子目录再试一次。
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = bundle.url(forResource: name, withExtension: nil)
            ?? bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
        guard let url else {
            throw FixtureError.missing(name)
        }
        return try Data(contentsOf: url)
    }
}

private final class BundleToken {}

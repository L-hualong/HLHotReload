//
//  HLHotReloadInjector.swift
//  HLHotReload
//
//  Created by 刘华龙 on 2020/3/21.
//  Copyright © 2020 刘华龙. All rights reserved.
//
import Foundation

fileprivate extension String {
    subscript(range: NSRange) -> String? {
        return Range(range, in: self).flatMap { String(self[$0]) }
    }
    func escaping(_ chars: String, with template: String = "\\$0") -> String {
        // 使用正则将c数值中的字符前面加上 //
        let c = "[\(chars)]"
        let temp = template.replacingOccurrences(of: "\\", with: "\\\\")
        return self.replacingOccurrences(of: c, with: temp, options: [.regularExpression])
    }
}

@objc
public class HLHotReloadInjector: NSObject {

    static var instance = HLHotReloadInjector()
    @objc public class func sharedInstance() -> HLHotReloadInjector {
        return instance
    }

    @objc public var frameworks = Bundle.main.privateFrameworksPath ?? Bundle.main.bundlePath + "/Frameworks"
    @objc public var arch = "x86_64"
    @objc public var xcodeDev = "/Applications/Xcode.app/Contents/Developer"
    @objc public var tmpDir = "/tmp/HLHotRelod_cache"
    
    @objc public var injectionNumber = 0
    static var compileByClass = [String: (String, String)]()

    static var buildCacheFile = "/tmp/HLHotReload_builds.plist"
    static var longTermCache = NSMutableDictionary(contentsOfFile: buildCacheFile) ?? NSMutableDictionary()

    @objc public var injectorError = {
        (_ message: String) -> Error in
        return NSError(domain: "HLHotReloadInjector", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    public func determineEnvironment(sourceFile: String) throws -> (URL) {
        let sourceURL = URL(fileURLWithPath: sourceFile)
        let derivedData = findDerivedData(url: URL(fileURLWithPath: NSHomeDirectory()))
        guard let logsDir = findProject(for: sourceURL, derivedData: derivedData!) else {
            throw injectorError("""
                        无法定位包含的项目或其日志。
                        对于macOS应用程序，您需要关闭应用程序沙箱。
                        你是否定制了DerivedData路径?
                        """)
        }
        return logsDir
    }

    @objc public func rebuildClass(sourceFile: String) throws -> String {
        let logsDir = try determineEnvironment(sourceFile: sourceFile)

        injectionNumber += 1
        let tmpfile = "\(tmpDir)/HLHotReload\(injectionNumber)"
        let logfile = "\(tmpfile).log"

        // 找到类的编译命令
        guard let (compileCommand, sourceFile) = try HLHotReloadInjector.compileByClass[sourceFile] ??
            findCompileCommand(logsDir: logsDir, sourceFile: sourceFile, tmpfile: tmpfile) ??
            HLHotReloadInjector.longTermCache[sourceFile].flatMap({ ($0 as! String, sourceFile) }) else {
            throw injectorError("无法找到编译命令")
        }

        // 执行编译命令
        guard shell(command: """
                (\(compileCommand) -o \(tmpfile).o >\(logfile) 2>&1)
                """) else {
            HLHotReloadInjector.compileByClass.removeValue(forKey: sourceFile)
            throw injectorError("Re-compilation failed (\(tmpDir)/command.sh)\n\(try! String(contentsOfFile: logfile))")
        }

        // 缓存编译命令
        HLHotReloadInjector.compileByClass[sourceFile] = (compileCommand, sourceFile)
        if HLHotReloadInjector.longTermCache[sourceFile] as? String != compileCommand && sourceFile.hasPrefix("/") {
            HLHotReloadInjector.longTermCache[sourceFile] = compileCommand
            HLHotReloadInjector.longTermCache.write(toFile: HLHotReloadInjector.buildCacheFile, atomically: false)
        }

        // 链接.o文件以创建动态库
        let toolchain = "\(xcodeDev)/Toolchains/XcodeDefault.xctoolchain"
        
        let osSpecific = "-isysroot \(xcodeDev)/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk -mios-simulator-version-min=9.0 -L\(toolchain)/usr/lib/swift/iphonesimulator -undefined dynamic_lookup"

        guard shell(command: """
            \(xcodeDev)/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang -arch "\(arch)" -bundle \(osSpecific) -dead_strip -Xlinker -objc_abi_version -Xlinker 2 -fobjc-arc \(tmpfile).o -L "\(frameworks)" -F "\(frameworks)" -rpath "\(frameworks)" -o \(tmpfile).dylib >>\(logfile) 2>&1
            """) else {
            throw injectorError("Link failed, check \(tmpDir)/command.sh\n\(try! String(contentsOfFile: logfile))")
        }

        // 对dylib进行签名
        guard shell(command: """
            export CODESIGN_ALLOCATE=\(xcodeDev)/Toolchains/XcodeDefault.xctoolchain/usr/bin/codesign_allocate; codesign --force -s '-' "\(tmpfile).dylib"
            """) else {
            throw injectorError("Codesign failed")
        }

        // 重置dylib以防止macOS 10.15阻塞它
        let filemgr = FileManager.default
        let url = URL(fileURLWithPath: "\(tmpfile).dylib")
        let dylib = try Data(contentsOf: url)
        try filemgr.removeItem(at: url)
        try dylib.write(to: url)

        return tmpfile
    }

    @objc public func extractClasSymbols(tmpfile: String) throws -> [String] {

        guard shell(command: """
            \(xcodeDev)/Toolchains/XcodeDefault.xctoolchain/usr/bin/nm \(tmpfile).o | grep -E ' S _OBJC_CLASS_\\$_| _(_T0|\\$S|\\$s).*CN$' | awk '{print $3}' >\(tmpfile).classes
            """) else {
            throw injectorError("Could not list class symbols")
        }
        guard var symbols = (try? String(contentsOfFile: "\(tmpfile).classes"))?.components(separatedBy: "\n") else {
            throw injectorError("Could not load class symbol list")
        }
        symbols.removeLast()

        return symbols
    }

    func findCompileCommand(logsDir: URL, sourceFile: String, tmpfile: String) throws -> (compileCommand: String, sourceFile: String)? {
        
        //https://www.cnblogs.com/f-ck-need-u/p/9648439.html
        
        //  \Q...\E，使得其失去正则表达式的含义，而仅作为普通字符串。
        let sourceRegex = "\\Q\(sourceFile)\\E"
        // 下面正则表达式的目前是搜索匹配出 " -c <sourceRegex>"
        // 匿名捕获(?:...)：仅分组，不捕获，所以后面无法再引用这个捕获
        let regexp = "(?:(-c \(sourceRegex)))"
        // 转义以下字符 \ " $
        let regexp2 = regexp.escaping("\"$")

        guard shell(command: """
            # 搜索构建日志，首先是最近的
            for log in `ls -t "\(logsDir.path)/"*.xcactivitylog`; do

                /usr/bin/env perl <(cat <<'PERL'
                    use JSON::PP;
                    use English;
                    use strict;

                    # Xcode日志中的行分隔符
                    $INPUT_RECORD_SEPARATOR = "\\r";

                    # xcactivitylog的格式是gzip，解压它
                    open GUNZIP, "/usr/bin/gunzip <\\"$ARGV[0]\\" 2>/dev/null |" or die;

                    # 将日志grep到匹配为止
                    while (defined (my $line = <GUNZIP>)) {
                        # 寻找编译命令
                        if ($line =~ m@\(regexp2)@o and $line =~ " \(arch)") {
                            # 停止搜索
                            print $line;
                            exit 0;
                        }
                    }
                    # 类/文件未找到
                    exit 1;
            PERL
                ) "$log" >"\(tmpfile).sh" && exit 0
            done
            exit 1;
            """) else {
            return nil
        }

        var compileCommand = try! String(contentsOfFile: "\(tmpfile).sh")
        compileCommand = compileCommand.components(separatedBy: " -o ")[0] + " "

        // 删除新构建系统中多余的转义
        compileCommand = compileCommand
            // logs of new build system escape ', $ and "
            .replacingOccurrences(of: "\\\\([\"'\\\\])", with: "$1", options: [.regularExpression])
            // pch文件可能不再存在
            .replacingOccurrences(of: " -pch-output-dir \\S+ ", with: " ", options: [.regularExpression])

        return (compileCommand, sourceFile)
    }

    func findDerivedData(url: URL) -> URL? {
        if url.path == "/" {
            return nil
        }

        let relativeDirs = "Library/Developer/Xcode/DerivedData"
        let derived = url.appendingPathComponent(relativeDirs)
        if FileManager.default.fileExists(atPath: derived.path) {
            return derived
        }
        return nil
    }

    func findProject(for source: URL, derivedData: URL) -> (URL)? {
        let dir = source.deletingLastPathComponent()
        if dir.path == "/" {
            return nil
        }

        var candidate = findProject(for: dir, derivedData: derivedData)

        if let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path),
            let project = file(withExt: "xcworkspace", in: files) ?? file(withExt: "xcodeproj", in: files),
            let logsDir = logsDir(project: dir.appendingPathComponent(project), derivedData: derivedData),
            mtime(logsDir) > candidate.flatMap({ _ in mtime(logsDir) }) ?? 0 {
                candidate = logsDir
        }

        return candidate
    }

    func file(withExt ext: String, in files: [String]) -> String? {
        return files.first { URL(fileURLWithPath: $0).pathExtension == ext }
    }

    func mtime(_ url: URL) -> time_t {
        var info = stat()
        return stat(url.path, &info) == 0 ? info.st_mtimespec.tv_sec : 0
    }

    func logsDir(project: URL, derivedData: URL) -> URL? {
        let filemgr = FileManager.default
        let projectPrefix = project.deletingPathExtension()
            .lastPathComponent.replacingOccurrences(of: "\\s+", with: "_",
                                    options: .regularExpression, range: nil)
        let relativeDerivedData = derivedData
            .appendingPathComponent("\(projectPrefix)/Logs/Build")

        return ((try? filemgr.contentsOfDirectory(atPath: derivedData.path))?
            .filter { $0.starts(with: projectPrefix + "-") }
            .map { derivedData.appendingPathComponent($0 + "/Logs/Build") }
            ?? [] + [relativeDerivedData])
            .filter { filemgr.fileExists(atPath: $0.path) }
            .sorted { mtime($0) > mtime($1) }
            .first
    }

    @objc @discardableResult public func shell(command: String) -> Bool {
        let commandFile = "\(tmpDir)/command.sh"
        try! command.write(toFile: commandFile, atomically: false, encoding: .utf8)
        let task = Process()
        task.launchPath = "/bin/bash"
        task.arguments = ["-c", command]
        task.launch()
        task.waitUntilExit()
        return task.terminationStatus == EXIT_SUCCESS
    }
}

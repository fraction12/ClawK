//
//  TalkTTSServerManager.swift
//  ClawK
//
//  Manages the Python TTS server process lifecycle
//

import Foundation
import os

private let logger = Logger(subsystem: "ai.openclaw.clawk", category: "talk-tts-server")

@MainActor
class TalkTTSServerManager {
    private var process: Process?
    private var hasRestarted = false
    private var livenessTask: Task<Void, Never>?

    func start() {
        if isPortInUse(8765) {
            logger.info("Port 8765 already in use, assuming TTS server is running")
            startLivenessChecks()
            return
        }
        launchProcess()
        startLivenessChecks()
    }

    func stop() {
        livenessTask?.cancel()
        livenessTask = nil
        if let process = process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
            logger.info("TTS server stopped")
        }
        process = nil
    }

    var isRunning: Bool { process?.isRunning ?? false }

    private var appSupportPythonEnv: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClawK/python-env").path
    }

    private func ensurePythonDeps() -> String? {
        let venvPath = appSupportPythonEnv
        let venvPython = venvPath + "/bin/python3"
        if FileManager.default.fileExists(atPath: venvPython) { return venvPython }

        let systemPythons = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
        guard let systemPython = systemPythons.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            logger.error("No system python3 found")
            return nil
        }

        let bundledReqs = Bundle.main.resourceURL?.appendingPathComponent("requirements.txt").path
        let devReqs = Bundle.main.bundlePath + "/../ClawK/Resources/requirements.txt"
        guard let reqsPath = [bundledReqs, devReqs].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            logger.warning("No requirements.txt found")
            return nil
        }

        try? FileManager.default.createDirectory(atPath: (venvPath as NSString).deletingLastPathComponent,
                                                  withIntermediateDirectories: true)

        let createVenv = Process()
        createVenv.executableURL = URL(fileURLWithPath: systemPython)
        createVenv.arguments = ["-m", "venv", venvPath]
        do {
            try createVenv.run()
            createVenv.waitUntilExit()
            guard createVenv.terminationStatus == 0 else {
                logger.error("Failed to create Python venv (exit \(createVenv.terminationStatus))")
                return nil
            }
        } catch {
            logger.error("Failed to run venv creation: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        let pip = venvPath + "/bin/pip3"
        let installDeps = Process()
        installDeps.executableURL = URL(fileURLWithPath: pip)
        installDeps.arguments = ["install", "-r", reqsPath]
        do {
            try installDeps.run()
            installDeps.waitUntilExit()
            guard installDeps.terminationStatus == 0 else {
                logger.error("pip install failed (exit \(installDeps.terminationStatus))")
                return nil
            }
        } catch {
            logger.error("Failed to run pip install: \(error.localizedDescription, privacy: .public)")
            return nil
        }

        logger.info("Python environment created at \(venvPath, privacy: .public)")
        return venvPython
    }

    private func launchProcess() {
        let bundledPath = Bundle.main.resourceURL?.appendingPathComponent("tts_server.py").path
        let devPath = Bundle.main.bundlePath + "/../ClawK/Resources/tts_server.py"

        guard let serverPath = [bundledPath, devPath].compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            logger.error("Could not find tts_server.py")
            return
        }

        let devVenvPython = Bundle.main.bundlePath + "/../Server/.venv/bin/python3"
        let appSupportPython = appSupportPythonEnv + "/bin/python3"

        let pythonPath: String
        if FileManager.default.fileExists(atPath: devVenvPython) {
            pythonPath = devVenvPython
        } else if FileManager.default.fileExists(atPath: appSupportPython) {
            pythonPath = appSupportPython
        } else if let created = ensurePythonDeps() {
            pythonPath = created
        } else {
            let systemPythons = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"]
            guard let fallback = systemPythons.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
                logger.error("Could not find python3")
                return
            }
            pythonPath = fallback
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = [serverPath]
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        proc.terminationHandler = { [weak self] terminatedProcess in
            let status = terminatedProcess.terminationStatus
            let reason = terminatedProcess.terminationReason
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if reason == .uncaughtSignal || status != 0 {
                    logger.warning("TTS server exited unexpectedly (status: \(status), reason: \(String(describing: reason)))")
                    if !self.hasRestarted {
                        self.hasRestarted = true
                        self.process = nil
                        try? await Task.sleep(for: .seconds(1))
                        logger.info("Restarting TTS server after crash")
                        self.launchProcess()
                    } else {
                        logger.error("TTS server crashed again, not restarting")
                        self.process = nil
                    }
                } else {
                    self.process = nil
                }
            }
        }

        do {
            try proc.run()
            process = proc
            logger.info("TTS server started with PID \(proc.processIdentifier)")
        } catch {
            logger.error("Failed to start TTS server: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func startLivenessChecks() {
        livenessTask?.cancel()
        livenessTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self = self else { return }
                guard self.process != nil else { continue }
                if !self.isPortInUse(8765) {
                    if let proc = self.process, !proc.isRunning, !self.hasRestarted {
                        logger.warning("TTS server liveness check failed, restarting")
                        self.hasRestarted = true
                        self.process = nil
                        self.launchProcess()
                    }
                }
            }
        }
    }

    func isPortInUse(_ port: Int) -> Bool {
        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(sock, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }
}

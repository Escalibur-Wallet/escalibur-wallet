import Darwin
import Foundation
import Observation
import MachO

/// Sinais de jailbreak e de depurador (docs/seguranca.md §7).
///
/// So aviso. Deteccao aqui e lombada: quem tem execucao de codigo contorna com
/// Frida, e um falso positivo trancaria o dono fora do proprio dinheiro. Ao detectar,
/// o app mostra uma faixa recomendando mover saldo alto para carteira de hardware.
/// Nunca bloqueia, nunca apaga, nunca avisa servidor nenhum.
enum DeviceIntegrity {
    /// Conferido na abertura, de novo a cada volta ao primeiro plano e antes de cada operacao com a chave
    /// raiz: um depurador ou uma biblioteca injetada depois do primeiro quadro tambem acende a faixa
    /// (auditoria das chaves de 06/11/2026). Acesa, fica acesa ate o app fechar. Observavel: a faixa
    /// aparece na hora, e nao so quando a tela redesenha por outro motivo.
    @MainActor @Observable final class Signal {
        static let shared = Signal()
        private(set) var suspicious = DeviceIntegrity.check()
        func recheck() { if !suspicious { suspicious = DeviceIntegrity.check() } }
    }

    @MainActor static var suspicious: Bool { Signal.shared.suspicious }

    @MainActor static func recheck() { Signal.shared.recheck() }

    static func check() -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        // No Mac, `/usr/sbin/sshd` e `/usr/bin/ssh` existem de fabrica: os caminhos do
        // jailbreak dariam alarme falso. O resto vale igual.
        return (!onMac && hasJailbreakFiles) || canWriteOutsideSandbox || hasInjectedLibraries || isBeingTraced
        #endif
    }

    /// O app de iPhone rodando num Mac com Apple Silicon.
    static var onMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }

    private static var hasJailbreakFiles: Bool {
        ["/var/jb", "/Applications/Cydia.app", "/Applications/Sileo.app", "/Applications/Zebra.app",
         "/usr/sbin/sshd", "/etc/apt", "/private/var/lib/apt", "/usr/bin/ssh"]
            .contains { FileManager.default.fileExists(atPath: $0) }
    }

    private static var canWriteOutsideSandbox: Bool {
        let path = "/private/escalibur-integridade"
        do {
            try Data([0]).write(to: URL(fileURLWithPath: path))
            try? FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    private static var hasInjectedLibraries: Bool {
        if ProcessInfo.processInfo.environment["DYLD_INSERT_LIBRARIES"] != nil { return true }
        let markers = ["frida", "substrate", "libhooker", "ellekit", "cycript", "substitute"]
        for index in 0..<_dyld_image_count() {
            guard let name = _dyld_get_image_name(index) else { continue }
            let lower = String(cString: name).lowercased()
            if markers.contains(where: lower.contains) { return true }
        }
        return false
    }

    private static var isBeingTraced: Bool {
        #if DEBUG
        return false
        #else
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return false }
        return info.kp_proc.p_flag & P_TRACED != 0
        #endif
    }
}

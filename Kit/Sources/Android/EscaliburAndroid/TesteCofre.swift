#if DEBUG
import EscaliburCore
import EscaliburKeys
import Foundation

/// So no build de depuracao: o cofre do iOS (RootKeyVault e WalletVault) sobre o Keystore de um
/// Android de verdade. Apaga o cofre do aparelho antes e depois: so roda no emulador de teste.
enum TesteCofre {
    /// `etapa`: "completo" (apaga no fim), "preparar" (deixa o cofre com a biometria ligada) e
    /// "conferir" (depois de cadastrar outra digital: a biometria antiga nao pode abrir mais).
    static func rodar(biometria: Bool, etapa: String) -> [String: String] {
        var resultado: [String: String] = [:]
        let store = KeystoreStore()
        let wrapper = KeystoreWrapper()
        let vault = RootKeyVault(store: store, wrapper: wrapper)
        if etapa == "conferir" {
            defer { vault.wipeAll() }
            resultado["cadastro mudou"] = "\(vault.biometryEnrollmentChanged)"
            resultado["chave da biometria"] = "\(wrapper.probeKey(.biometry))"
            do {
                let aberta = try vault.unlockWithBiometry(reason: "Abrir a Escalibur")
                aberta.wipe()
                resultado["abrir pela biometria"] = "ABRIU COM O CADASTRO NOVO"
            } catch {
                resultado["abrir pela biometria"] = "recusado: \(error)"
            }
            resultado["biometria ligada depois"] = "\(vault.isBiometryEnabled)"
            return resultado
        }
        vault.wipeAll()
        defer { if etapa != "preparar" { vault.wipeAll() } }

        func medir(_ nome: String, _ corpo: () throws -> String) {
            let inicio = Date()
            do {
                let saida = try corpo()
                resultado[nome] = "\(saida) (\(Int(Date().timeIntervalSince(inicio) * 1000)) ms)"
            } catch {
                resultado[nome] = "ERRO \(error) (\(Int(Date().timeIntervalSince(inicio) * 1000)) ms)"
            }
        }
        func pin(_ texto: String) -> SecureBytes {
            let bytes = Array(texto.utf8)
            let segredo = SecureBytes(capacity: bytes.count)
            bytes.withUnsafeBufferPointer { segredo.append(contentsOf: $0) }
            return segredo
        }

        var rk: SecureBytes?
        medir("1 cadastro") {
            rk = try vault.setUp(pin: pin("246810"))
            return "rk \(rk?.count ?? 0) bytes, isSetUp \(vault.isSetUp)"
        }
        medir("2 PIN certo") {
            let aberta = try vault.unlock(pin: pin("246810"))
            defer { aberta.wipe() }
            return Hash.constantTimeEqual(aberta, rk!) ? "a mesma RK" : "RK DIFERENTE"
        }
        medir("3 PIN errado") {
            do {
                _ = try vault.unlock(pin: pin("135790"))
                return "ABRIU COM O PIN ERRADO"
            } catch RootKeyVault.Failure.wrongPIN(let restantes) {
                return "recusado (antes de apagar: \(restantes.map(String.init) ?? "nunca"))"
            }
        }
        medir("4 atraso depois do erro") { "\(Int(vault.throttleRemaining())) s, erros \(vault.failureCount())" }
        medir("5 carteira gravada e aberta") {
            let carteiras = WalletVault(store: store)
            let id = UUID()
            let entropia = try SecureBytes.random(count: 16)
            let original = entropia.withUnsafeBytes { Array($0) }
            try carteiras.save(WalletSecret(entropy: entropia, language: .english, passphrase: SecureBytes(capacity: 1)), walletID: id, rk: rk!)
            let aberta = try carteiras.open(walletID: id, rk: rk!)
            defer { aberta.wipe() }
            let igual = aberta.entropy.withUnsafeBytes { Array($0) } == original
            let errada = try SecureBytes.random(count: 32)
            let recusada = (try? carteiras.open(walletID: id, rk: errada)) == nil
            return igual && recusada ? "a mesma entropia; RK errada recusada" : "FALHOU (igual \(igual), recusada \(recusada))"
        }
        medir("6 chaves no hardware") {
            [WrapSlot.device, .pin, .biometry].map { "\($0.rawValue): \(wrapper.probeKey($0))" }.joined(separator: ", ")
        }
        if biometria {
            medir("7 ligar a biometria") {
                try vault.enableBiometry(rk: rk!, reason: "Ligar a biometria")
                return "ligada: \(vault.isBiometryEnabled)"
            }
            medir("8 abrir pela biometria") {
                let aberta = try vault.unlockWithBiometry(reason: "Abrir a Escalibur")
                defer { aberta.wipe() }
                return Hash.constantTimeEqual(aberta, rk!) ? "a mesma RK" : "RK DIFERENTE"
            }
        }
        rk?.wipe()
        return resultado
    }
}
#endif

import CJNI
import EscaliburCore
import Foundation

/// A maquina virtual do Java e os metodos do app que o nucleo chama: a rede (Rede.kt) e o cofre
/// (Cofre.kt). Ligados no JNI_OnLoad, na thread do Java que carregou a biblioteca: so ela enxerga
/// as classes do app. As threads do nucleo nao sao do Java e se prendem a maquina a cada chamada.
enum Java {
    struct Metodo: @unchecked Sendable {
        let classe: jclass
        let id: jmethodID
    }

    private struct Ligacao: @unchecked Sendable {
        let vm: UnsafeMutablePointer<JavaVM?>
        let classeString: jclass
        let metodos: [String: Metodo]
    }

    /// Classe, metodo e assinatura de tudo que o nucleo chama. O proguard-rules.pro mantem cada um.
    static let assinaturas: [(String, String, String)] = [
        ("Rede", "requisitar", "(JLjava/lang/String;Ljava/lang/String;[Ljava/lang/String;[BIII)[B"),
        ("Rede", "cancelar", "(J)V"),
        ("Cofre", "ler", "(Ljava/lang/String;[B)[B"),
        ("Cofre", "gravar", "(Ljava/lang/String;[BI[BZ)I"),
        ("Cofre", "apagar", "(Ljava/lang/String;)I"),
        ("Cofre", "apagarTudo", "()I"),
        ("Cofre", "sondar", "(Ljava/lang/String;)I"),
        ("Cofre", "criarChave", "(Ljava/lang/String;)I"),
        ("Cofre", "sondarChave", "(Ljava/lang/String;)I"),
        ("Cofre", "apagarChave", "(Ljava/lang/String;)V"),
        ("Cofre", "embrulhar", "(Ljava/lang/String;[B[B)[B"),
        ("Cofre", "desembrulhar", "(Ljava/lang/String;[B[BLjava/lang/String;)[B"),
        ("Cofre", "desembrulharVigiando", "(Ljava/lang/String;[BLjava/lang/String;Ljava/lang/String;[B)[B"),
        ("Cofre", "estadoDaBiometria", "()I"),
        ("Cofre", "cadastroDaBiometria", "()[B"),
        ("Cofre", "boot", "()[B"),
        ("Eventos", "emitir", "(Ljava/lang/String;Ljava/lang/String;)V"),
    ]

    /// Gravada uma vez no JNI_OnLoad, antes de a biblioteca voltar ao Java: toda leitura vem depois.
    nonisolated(unsafe) private static var ligacao: Ligacao?

    /// Nil se faltar alguma classe ou metodo (o APK nao e este): sem rede e sem cofre.
    static func ligar(_ vm: UnsafeMutablePointer<JavaVM?>, _ java: JavaEnv) -> Bool {
        guard let classeString = java.globalClass("java/lang/String") else { return false }
        var classes: [String: jclass] = [:]
        var metodos: [String: Metodo] = [:]
        for (nomeDaClasse, nome, assinatura) in assinaturas {
            if classes[nomeDaClasse] == nil {
                guard let classe = java.globalClass("app/escalibur/wallet/nucleo/" + nomeDaClasse) else { return false }
                classes[nomeDaClasse] = classe
            }
            guard let classe = classes[nomeDaClasse], let id = java.staticMethod(classe, nome, assinatura) else { return false }
            metodos[nomeDaClasse + "." + nome] = Metodo(classe: classe, id: id)
        }
        ligacao = Ligacao(vm: vm, classeString: classeString, metodos: metodos)
        return true
    }

    static var classeString: jclass? { ligacao?.classeString }

    static func metodo(_ nome: String) throws -> Metodo {
        guard let metodo = ligacao?.metodos[nome] else { throw URLError(.notConnectedToInternet) }
        return metodo
    }

    /// Prende a thread a maquina virtual do Java pelo tempo da chamada (se ainda nao estava).
    static func naMaquina<T>(_ corpo: (JavaEnv) throws -> T) throws -> T {
        guard let vm = ligacao?.vm else { throw URLError(.notConnectedToInternet) }
        let interface = vm.pointee!.pointee
        var bruto: UnsafeMutableRawPointer?
        if interface.GetEnv(vm, &bruto, jint(JNI_VERSION_1_6)) == JNI_OK, let bruto {
            return try corpo(JavaEnv(env: bruto.assumingMemoryBound(to: JNIEnv?.self)))
        }
        var env: UnsafeMutablePointer<JNIEnv?>?
        guard interface.AttachCurrentThread(vm, &env, nil) == JNI_OK, let env else { throw URLError(.notConnectedToInternet) }
        defer { _ = interface.DetachCurrentThread(vm) }
        return try corpo(JavaEnv(env: env))
    }
}

extension JavaEnv {
    func callStaticInt(_ metodo: Java.Metodo, _ arguments: [jvalue]) -> jint? {
        let result = arguments.withUnsafeBufferPointer { table.CallStaticIntMethodA(env, metodo.classe, metodo.id, $0.baseAddress) }
        guard table.ExceptionCheck(env) == JNI_FALSE else {
            table.ExceptionClear(env)
            return nil
        }
        return result
    }

    func callStatic(_ metodo: Java.Metodo, _ arguments: [jvalue]) -> jobject? {
        callStatic(metodo.classe, metodo.id, arguments)
    }

    func callStaticVoid(_ metodo: Java.Metodo, _ arguments: [jvalue]) {
        callStaticVoid(metodo.classe, metodo.id, arguments)
    }

    /// Um segredo que o Kotlin devolveu num byte[]: copiado direto para o buffer seguro a partir
    /// de `inicio`, e o byte[] zerado no lugar antes de soltar.
    func secureBytes(_ array: jobject?, from inicio: Int, count: Int? = nil) -> SecureBytes? {
        guard let array else { return nil }
        let total = Int(table.GetArrayLength(env, array))
        let tamanho = count ?? (total - inicio)
        guard inicio >= 0, tamanho >= 0, inicio + tamanho <= total else { return nil }
        guard let pointer = table.GetPrimitiveArrayCritical(env, array, nil) else { return nil }
        let segredo = SecureBytes(capacity: max(tamanho, 1))
        segredo.fill(count: tamanho) { destino in
            destino.copyMemory(from: pointer.advanced(by: inicio), byteCount: tamanho)
        }
        memset_s(pointer, total, 0, total)
        table.ReleasePrimitiveArrayCritical(env, array, pointer, 0)
        return segredo
    }

    /// O primeiro byte de um byte[] (o codigo de uma resposta do cofre), sem tocar o resto.
    func firstByte(_ array: jobject?) -> UInt8? {
        guard let array, table.GetArrayLength(env, array) > 0 else { return nil }
        var byte: jbyte = 0
        table.GetByteArrayRegion(env, array, 0, 1, &byte)
        return UInt8(bitPattern: byte)
    }

    /// Um byte[] novo com o segredo (o Kotlin zera depois de usar).
    func byteArray(_ segredo: SecureBytes) -> jbyteArray? {
        guard let array = table.NewByteArray(env, jsize(segredo.count)) else { return nil }
        segredo.withUnsafeBytes { table.SetByteArrayRegion(env, array, 0, jsize(segredo.count), $0.bindMemory(to: jbyte.self).baseAddress) }
        return array
    }

    func booleano(_ value: Bool) -> jboolean { value ? jboolean(JNI_TRUE) : jboolean(JNI_FALSE) }
}

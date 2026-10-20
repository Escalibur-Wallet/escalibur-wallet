// A ponte entre o app Android (Kotlin) e o nucleo, pelo JNI. So no build Android.
//
// Um ponto de entrada so para o que nao e segredo: o Kotlin chama um metodo pelo nome, com os
// dados em JSON, e recebe JSON (`Nucleo.chamar`). Segredo (frase, PIN, chave raiz) nunca passa
// por String: vai em ByteBuffer direto, fora do heap do Java, e quem recebe zera.
import CJNI
import EscaliburCore
import Foundation

/// O ambiente do JNI de uma chamada: as funcoes da tabela do Java, com nomes do Swift.
struct JavaEnv {
    let env: UnsafeMutablePointer<JNIEnv?>

    var table: JNINativeInterface { env.pointee!.pointee }

    func string(_ value: jstring?) -> String? {
        guard let value, let chars = table.GetStringUTFChars(env, value, nil) else { return nil }
        defer { table.ReleaseStringUTFChars(env, value, chars) }
        return String(cString: chars)
    }

    func string(_ text: String) -> jstring? {
        text.withCString { table.NewStringUTF(env, $0) }
    }

    /// O conteudo de um ByteBuffer direto (o segredo fica onde o Kotlin pos, fora do heap do
    /// Java). Nil se nao for direto.
    func directBuffer(_ buffer: jobject?) -> UnsafeMutableRawBufferPointer? {
        guard let buffer, let address = table.GetDirectBufferAddress(env, buffer) else { return nil }
        let capacity = table.GetDirectBufferCapacity(env, buffer)
        guard capacity >= 0 else { return nil }
        return UnsafeMutableRawBufferPointer(start: address, count: Int(capacity))
    }

    func stringArray(_ values: [String], classe: jclass) -> jobjectArray? {
        guard let array = table.NewObjectArray(env, jsize(values.count), classe, nil) else { return nil }
        for (index, value) in values.enumerated() {
            let item = string(value)
            table.SetObjectArrayElement(env, array, jsize(index), item)
            deleteLocal(item)
        }
        return array
    }

    func byteArray(_ data: Data) -> jbyteArray? {
        guard let array = table.NewByteArray(env, jsize(data.count)) else { return nil }
        data.withUnsafeBytes { table.SetByteArrayRegion(env, array, 0, jsize(data.count), $0.bindMemory(to: jbyte.self).baseAddress) }
        return array
    }

    func bytes(_ array: jobject?) -> Data? {
        guard let array else { return nil }
        let count = Int(table.GetArrayLength(env, array))
        var data = Data(count: count)
        data.withUnsafeMutableBytes { table.GetByteArrayRegion(env, array, 0, jsize(count), $0.bindMemory(to: jbyte.self).baseAddress) }
        return data
    }

    /// Uma classe que fica valida fora desta chamada (o JNI_OnLoad guarda as que a rede usa).
    func globalClass(_ name: String) -> jclass? {
        guard let local = table.FindClass(env, name) else { return clearException() }
        defer { deleteLocal(local) }
        return table.NewGlobalRef(env, local)
    }

    func staticMethod(_ classe: jclass, _ name: String, _ signature: String) -> jmethodID? {
        table.GetStaticMethodID(env, classe, name, signature) ?? clearException()
    }

    /// Nil se o Kotlin lancou excecao (ela e limpa aqui).
    func callStatic(_ classe: jclass, _ method: jmethodID, _ arguments: [jvalue]) -> jobject? {
        let result = arguments.withUnsafeBufferPointer { table.CallStaticObjectMethodA(env, classe, method, $0.baseAddress) }
        guard table.ExceptionCheck(env) == JNI_FALSE else {
            deleteLocal(result)
            return clearException()
        }
        return result
    }

    func callStaticVoid(_ classe: jclass, _ method: jmethodID, _ arguments: [jvalue]) {
        arguments.withUnsafeBufferPointer { table.CallStaticVoidMethodA(env, classe, method, $0.baseAddress) }
        if table.ExceptionCheck(env) != JNI_FALSE { table.ExceptionClear(env) }
    }

    func deleteLocal(_ reference: jobject?) {
        if let reference { table.DeleteLocalRef(env, reference) }
    }

    private func clearException<T>() -> T? {
        if table.ExceptionCheck(env) != JNI_FALSE { table.ExceptionClear(env) }
        return nil
    }
}

/// Roda uma operacao assincrona do nucleo e espera o resultado. O Kotlin chama a ponte de uma
/// thread de fundo (Dispatchers.IO), nunca da thread da interface.
private final class Caixa<T>: @unchecked Sendable { var resultado: Result<T, Error>? }

func esperar<T: Sendable>(_ operacao: @escaping @Sendable () async throws -> T) throws -> T {
    let caixa = Caixa<T>()
    let pronto = DispatchSemaphore(value: 0)
    Task.detached {
        do { caixa.resultado = .success(try await operacao()) } catch { caixa.resultado = .failure(error) }
        pronto.signal()
    }
    pronto.wait()
    return try caixa.resultado!.get()
}

/// Quando o Kotlin carrega a biblioteca: liga a rede do nucleo ao transporte do Android e o cofre
/// ao Keystore. Se faltar alguma classe do app, o nucleo fica sem rede (nao volta para a libcurl)
/// e sem cofre.
@_cdecl("JNI_OnLoad")
public func JNI_OnLoad(_ vm: UnsafeMutablePointer<JavaVM?>, _ reservado: UnsafeMutableRawPointer?) -> jint {
    var bruto: UnsafeMutableRawPointer?
    guard vm.pointee!.pointee.GetEnv(vm, &bruto, jint(JNI_VERSION_1_6)) == JNI_OK, let bruto else { return JNI_ERR }
    if Java.ligar(vm, JavaEnv(env: bruto.assumingMemoryBound(to: JNIEnv?.self))) {
        Rede.instalar()
        Cofre.instalar()
    }
    return jint(JNI_VERSION_1_6)
}

@_cdecl("Java_app_escalibur_wallet_nucleo_Nucleo_chamar")
public func Java_app_escalibur_wallet_nucleo_Nucleo_chamar(
    _ env: UnsafeMutablePointer<JNIEnv?>, _ classe: jclass?, _ metodo: jstring?, _ corpo: jstring?
) -> jstring? {
    let java = JavaEnv(env: env)
    let nome = java.string(metodo) ?? ""
    let entrada = Data((java.string(corpo) ?? "{}").utf8)
    let resposta: Data
    do {
        resposta = try Nucleo.chamar(nome, entrada)
    } catch {
        resposta = Nucleo.erro(error)
    }
    return java.string(String(decoding: resposta, as: UTF8.self))
}

/// O mesmo ponto de entrada, para operacoes com segredo: o PIN, as palavras ou a passphrase vem
/// num byte[], que e copiado direto para o buffer seguro e zerado no lugar antes de soltar.
@_cdecl("Java_app_escalibur_wallet_nucleo_Nucleo_chamarComSegredo")
public func Java_app_escalibur_wallet_nucleo_Nucleo_chamarComSegredo(
    _ env: UnsafeMutablePointer<JNIEnv?>, _ classe: jclass?, _ metodo: jstring?, _ corpo: jstring?, _ segredo: jbyteArray?
) -> jstring? {
    let java = JavaEnv(env: env)
    let nome = java.string(metodo) ?? ""
    let entrada = Data((java.string(corpo) ?? "{}").utf8)
    let bytes = java.secureBytes(segredo, from: 0) ?? SecureBytes(capacity: 1)
    let resposta: Data
    do {
        resposta = try Nucleo.chamarComSegredo(nome, entrada, bytes)
    } catch {
        resposta = Nucleo.erro(error)
    }
    bytes.wipe()
    return java.string(String(decoding: resposta, as: UTF8.self))
}

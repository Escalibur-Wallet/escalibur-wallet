import Foundation

/// Onde ficam as listas embarcadas: as palavras do BIP-39 (conferidas por digesto ao carregar)
/// e as listas da forca da senha.
public enum CoreResources {
    #if os(Android)
    /// No Android o app copia as listas do APK para a pasta dele e diz onde ficaram: o
    /// `Bundle.module` do SwiftPM procura ao lado do executavel, que no Android e o do sistema.
    nonisolated(unsafe) public static var directory: String?
    #endif

    static var bundle: Bundle {
        #if os(Android)
        if let directory, let bundle = Bundle(path: directory) { return bundle }
        #endif
        return .module
    }
}

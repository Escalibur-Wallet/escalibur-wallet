import Foundation

/// O caminho de um arquivo do repositorio a partir de `#filePath`. Num aparelho Android, onde
/// o repositorio do Mac nao existe, os testes rodam com uma copia dele em `ESCALIBUR_RAIZ`, e o
/// comeco do caminho (`ESCALIBUR_RAIZ_MAC`) e trocado. No Mac, o caminho fica como esta.
func caminhoNoAparelho(_ caminho: String) -> String {
    let ambiente = ProcessInfo.processInfo.environment
    guard let raiz = ambiente["ESCALIBUR_RAIZ"], let mac = ambiente["ESCALIBUR_RAIZ_MAC"], caminho.hasPrefix(mac) else { return caminho }
    return raiz + caminho.dropFirst(mac.count)
}

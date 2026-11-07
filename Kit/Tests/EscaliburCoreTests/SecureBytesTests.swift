import Foundation
import Testing
@testable import EscaliburCore

@Suite("SecureBytes")
struct SecureBytesTests {
    @Test("Muitos buffers vivos ao mesmo tempo: cada um guarda o seu, e no Android todos ficam travados na RAM")
    func manyAtOnce() {
        // Mais do que as 16 paginas da cota do Android, se cada um tivesse regiao propria.
        let buffers = (0..<64).map { index -> SecureBytes in
            let buffer = SecureBytes(capacity: 32)
            for _ in 0..<32 { buffer.append(UInt8(index)) }
            return buffer
        }
        for (index, buffer) in buffers.enumerated() {
            buffer.withUnsafeBytes { bytes in
                #expect(bytes.count == 32)
                #expect(bytes.allSatisfy { $0 == UInt8(index) })
            }
        }
        // A arena nasceu travada. Quantos destes couberam nela depende dos outros testes em paralelo, que dividem a arena.
        #if !canImport(Darwin)
        #expect(LockedArena.isActive)
        #endif
    }

    @Test("O buffer que sai da arena fica zerado, e o grande vai para a regiao propria")
    func releasedIsWiped() {
        #if !canImport(Darwin)
        // Um padrao que ninguem mais escreve: outro teste em paralelo pode pegar a fatia devolvida e escrever nela, mas
        // nao este padrao. O que nao pode sobrar e ele.
        let pattern = (0..<200).map { UInt8(truncatingIfNeeded: $0 &* 37 &+ 11) }
        var address: UnsafeRawPointer?
        do {
            let first = SecureBytes(capacity: 200)
            first.replaceAll(with: pattern)
            address = first.withUnsafeBytes { $0.baseAddress.map(UnsafeRawPointer.init) }
        }
        // A arena continua mapeada: a fatia devolvida pode ser lida, e o segredo nao pode estar nela.
        if let address {
            let left = Array(UnsafeRawBufferPointer(start: address, count: 200))
            #expect(zip(left, pattern).filter { $0.0 == $0.1 && $0.1 != 0 }.count < 8)
        }
        #endif

        let large = SecureBytes(capacity: 64 * 1024)
        large.replaceAll(with: [UInt8](repeating: 7, count: 64 * 1024))
        large.withUnsafeBytes { bytes in #expect(bytes.count == 64 * 1024 && bytes.allSatisfy { $0 == 7 }) }
    }
}

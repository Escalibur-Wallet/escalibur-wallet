import Testing
@testable import EscaliburChains

/// A troca que reverteria pelo minimo (a moeda que cobra taxa na compra ou na venda) tem a mensagem
/// dela, e nao a de falha generica (03/11/2026).
@Suite("Troca abaixo do minimo na simulacao")
struct TradeBelowMinimumTests {
    @Test("Os motivos dos roteadores para o que chega abaixo do minimo; o resto e falha comum")
    func reasons() {
        for reason in ["execution reverted: Too little received", "execution reverted: PancakeRouter: INSUFFICIENT_OUTPUT_AMOUNT",
                       "execution reverted: UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT", "Return amount is not enough",
                       "execution reverted: ReturnAmountIsNotEnough", "TooMuchSlippage"] {
            #expect(TradeSimulationCheck.belowMinimum(reason), "\(reason)")
        }
        for reason in [nil, "execution reverted", "execution reverted: TransferHelper: TRANSFER_FROM_FAILED", "out of gas",
                       "execution reverted: Trading not enabled"] {
            #expect(!TradeSimulationCheck.belowMinimum(reason), "\(reason ?? "nil")")
        }
    }
}

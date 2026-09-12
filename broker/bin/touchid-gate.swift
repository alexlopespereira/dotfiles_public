// touchid-gate — portão biométrico do av-broker.
//
// Existe porque a conta de uso diário é PADRÃO, não-admin (checklist 1.5): o
// caminho usual de Touch ID em script (`sudo` com pam_tid, item 2.3) não está
// disponível para ela. LocalAuthentication funciona para qualquer usuário e
// ancora a aprovação no Secure Enclave — o chip devolve só sim/não.
//
// Compilado sob demanda pelo av-broker (cache por hash da fonte).
//
// Saída:  0 = aprovado   1 = negado pelo humano   2 = biometria indisponível
// O código 2 é o que faz o broker cair no desafio digitado, em vez de travar.

import Foundation
import LocalAuthentication

// --probe: só responde se a biometria existe, SEM mostrar diálogo. É o que
// permite ao broker escolher o portão na largada em vez de descobrir na hora
// (e imprimir um aviso de falha a cada aprovação).
let probeOnly = CommandLine.arguments.contains("--probe")

let reason = CommandLine.arguments.count > 1 && !probeOnly
    ? CommandLine.arguments[1]
    : "autorizar cunhagem de credencial"

let ctx = LAContext()
ctx.localizedFallbackTitle = ""   // sem "usar senha": o gesto é o controle

var probe: NSError?
guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &probe) else {
    let msg = probe?.localizedDescription ?? "motivo desconhecido"
    FileHandle.standardError.write("touchid-gate: indisponível (\(msg))\n".data(using: .utf8)!)
    exit(2)
}

if probeOnly { exit(0) }   // disponível, e nada foi mostrado ao usuário

let sem = DispatchSemaphore(value: 0)
var approved = false
var failure: Error?

ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { ok, err in
    approved = ok
    failure = err
    sem.signal()
}
sem.wait()

if !approved, let err = failure as NSError?,
   err.code != LAError.userCancel.rawValue,
   err.code != LAError.authenticationFailed.rawValue {
    // Falha de sistema (não uma negativa humana): sai 2 para o broker
    // oferecer o fallback, em vez de tratar como "usuário negou".
    FileHandle.standardError.write(
        "touchid-gate: falha (\(err.localizedDescription))\n".data(using: .utf8)!)
    exit(2)
}

exit(approved ? 0 : 1)

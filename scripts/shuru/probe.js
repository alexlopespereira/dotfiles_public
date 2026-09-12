#!/usr/bin/env node
// Sondas de rede de baixo nivel para o gate adversarial da Fase 2.
//
// Por que node e nao nc/dig: a imagem-base nao tem nenhum dos dois, mas TEM
// node — e essa e a ferramenta que um agente comprometido de fato teria em
// maos. Testar com o runtime do proprio agente e testar o ataque real, nao uma
// aproximacao.
//
// Cada sonda imprime UMA linha: CONECTOU | BLOQUEADO:<motivo> | TIMEOUT.
// A distincao importa: um gate que trata erro de ferramenta como "bloqueado"
// da falso-verde exatamente quando voce mais precisa da verdade.

const net = require('net');
const tls = require('tls');
const dgram = require('dgram');

const TIMEOUT_MS = 8000;
const [, , modo, alvo, porta, extra] = process.argv;

function fim(linha) { console.log(linha); process.exit(0); }

// Um unico caminho de saida para os tres desfechos, para que nenhuma sonda
// possa "vazar" sem imprimir nada e ser lida como silencio benigno.
function armar(sock, ao_conectar) {
  const t = setTimeout(() => fim('TIMEOUT'), TIMEOUT_MS);
  sock.on('error', (e) => { clearTimeout(t); fim(`BLOQUEADO:${e.code || e.message}`); });
  sock.on('close', () => { clearTimeout(t); fim('BLOQUEADO:fechado-sem-conectar'); });
  sock.once(ao_conectar, () => { clearTimeout(t); fim('CONECTOU'); });
}

switch (modo) {
  // TCP cru: sem TLS, sem HTTP, sem cooperacao de nenhuma variavel de ambiente.
  //
  // ⚠️ O QUE SE MEDE AQUI NAO E connect(). Medido em 29/jul/2026: o shuru tem
  // pilha TCP em modo usuario, e ela ACEITA O HANDSHAKE LOCALMENTE antes de
  // decidir se abre a saida. connect() para 192.0.2.1 (TEST-NET-1, RFC 5737,
  // inalcancavel por definicao) "tem sucesso" — logo, sucesso de connect() nao
  // prova alcance nenhum. A primeira versao deste gate acusou 13 vazamentos
  // inexistentes por medir isso.
  //
  // O sinal honesto e byte de volta: so o outro lado real pode envia-lo.
  case 'tcp': {
    const s = net.connect({ host: alvo, port: Number(porta) });
    let recebidos = 0, amostra = '';
    const t = setTimeout(() => {
      s.destroy();
      fim(recebidos ? `RECEBEU:${recebidos}B:${amostra}` : 'SEM-DADOS');
    }, TIMEOUT_MS);
    // Portas em que o servidor fala primeiro (22 SSH, 25 SMTP, 5900 VNC)
    // dispensam payload; as demais precisam de um empurrao para responder.
    // O payload vem por palavra-chave e nao literal porque `\r\n` nao
    // sobrevive a substituicao de comando no /bin/sh que chama isto.
    const payloads = {
      http: 'HEAD / HTTP/1.0\r\nHost: x\r\n\r\n',
      irc: 'NICK sonda\r\nUSER sonda 0 * :sonda\r\n',
    };
    s.on('connect', () => { if (payloads[extra]) s.write(payloads[extra]); });
    s.on('data', (d) => {
      recebidos += d.length;
      if (!amostra) amostra = JSON.stringify(d.slice(0, 32).toString('utf8'));
    });
    s.on('error', (e) => { clearTimeout(t); fim(`BLOQUEADO:${e.code || e.message}`); });
    break;
  }

  // TLS com SNI escolhido a dedo. `extra` e o servername; se o proxy so olha
  // SNI, apontar um IP nao-permitido com SNI permitido passaria.
  case 'tls': {
    const s = tls.connect({
      host: alvo, port: Number(porta), servername: extra || alvo,
      rejectUnauthorized: false,   // o que se mede aqui e alcance, nao confianca
    });
    armar(s, 'secureConnect');
    break;
  }

  // UDP e sem conexao: "bloqueado" so se manifesta como ausencia de resposta.
  // Por isso o desfecho bom aqui e TIMEOUT, e o ruim e RESPONDEU.
  case 'udp-dns': {
    const s = dgram.createSocket('udp4');
    // Query DNS A minima para "exemplo-nao-permitido.com", montada na mao.
    const nome = (extra || 'example.com').split('.');
    const partes = [Buffer.from([0x13, 0x37, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 0])];
    for (const p of nome) partes.push(Buffer.from([p.length]), Buffer.from(p));
    partes.push(Buffer.from([0, 0, 1, 0, 1]));
    const q = Buffer.concat(partes);
    const t = setTimeout(() => { s.close(); fim('TIMEOUT'); }, TIMEOUT_MS);
    s.on('message', (msg) => {
      clearTimeout(t);
      // ANCOUNT > 0 significa resposta com resultado, nao so um NXDOMAIN.
      const respostas = msg.readUInt16BE(6);
      s.close(); fim(`RESPONDEU:ancount=${respostas}`);
    });
    s.on('error', (e) => { clearTimeout(t); fim(`BLOQUEADO:${e.code || e.message}`); });
    s.send(q, Number(porta) || 53, alvo);
    break;
  }

  // UDP/443: se passar, HTTP/3 com ECH sai por baixo de qualquer allowlist por
  // SNI (research/egress.md §4.5). Aqui basta provar que nao ha resposta.
  case 'udp-quic': {
    const s = dgram.createSocket('udp4');
    const t = setTimeout(() => { s.close(); fim('TIMEOUT'); }, TIMEOUT_MS);
    s.on('message', () => { clearTimeout(t); s.close(); fim('RESPONDEU'); });
    s.on('error', (e) => { clearTimeout(t); fim(`BLOQUEADO:${e.code || e.message}`); });
    s.send(Buffer.alloc(64, 0x42), Number(porta) || 443, alvo);
    break;
  }

  default:
    console.log('BLOQUEADO:modo-desconhecido');
    process.exit(0);
}

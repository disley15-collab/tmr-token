// Confere que o código publicado na Tron mainnet é exatamente o compilado deste repositório.
// Checks that the code deployed on Tron mainnet is exactly what this repository compiles to.
//
//   npm install && forge build && npm run verificar
//
// Sem dependências: lê out/ do Foundry e pede o código on-chain à TronGrid (JSON-RPC público).
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const TOKEN = "TR7NKZVUjuK6udGYNPoCAwpsshD8fhLj6t";
const RPC = process.env.TRON_JSONRPC || "https://api.trongrid.io/jsonrpc";
const TETO_ESPERADO = (2n ** 64n - 1n) * 10n ** 12n; // 18.446.744.073.709,551615 TMR (immutable `teto`)

const B58 = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";
function tronParaHex(endereco) {
  let v = 0n;
  for (const c of endereco) v = v * 58n + BigInt(B58.indexOf(c));
  const bytes = Buffer.from(v.toString(16).padStart(50, "0"), "hex"); // 0x41 + 20 bytes + 4 de checksum
  const corpo = bytes.subarray(0, 21), soma = bytes.subarray(21);
  const h = crypto.createHash("sha256");
  const conf = crypto.createHash("sha256").update(h.update(corpo).digest()).digest().subarray(0, 4);
  if (corpo[0] !== 0x41 || !conf.equals(soma)) throw new Error("endereço Tron inválido");
  return "0x" + corpo.subarray(1).toString("hex");
}

(async () => {
  const art = JSON.parse(fs.readFileSync(path.join(__dirname, "../out/TokenSimples.sol/TokenSimples.json"), "utf8"));
  const compilado = art.deployedBytecode.object.replace(/^0x/, "");
  const r = await fetch(RPC, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_getCode", params: [tronParaHex(TOKEN), "latest"] }),
  }).then((x) => x.json());
  const onchain = String(r.result || "").replace(/^0x/, "");
  if (!onchain) throw new Error("não veio código on-chain: " + JSON.stringify(r));

  // `teto` é immutable: o compilador deixa zeros nessas posições e a publicação grava o valor.
  let esperado = compilado;
  const refs = Object.values(art.deployedBytecode.immutableReferences || {}).flat();
  const teto = "0x" + TETO_ESPERADO.toString(16).padStart(64, "0");
  for (const { start, length } of refs) {
    const valor = onchain.slice(start * 2, (start + length) * 2);
    if ("0x" + valor !== teto) throw new Error(`immutable em ${start} = 0x${valor}, esperado ${teto}`);
    esperado = esperado.slice(0, start * 2) + valor + esperado.slice((start + length) * 2);
  }

  const igual = esperado === onchain;
  console.log(`token        ${TOKEN} (${tronParaHex(TOKEN)})`);
  console.log(`on-chain     ${onchain.length / 2} bytes, sha256 ${crypto.createHash("sha256").update(Buffer.from(onchain, "hex")).digest("hex")}`);
  console.log(`compilado    ${compilado.length / 2} bytes, ${refs.length} posição(ões) de immutable (teto)`);
  console.log(igual ? "IGUAL ✓ o código publicado é exatamente o deste repositório" : "DIFERENTE ✗");
  process.exit(igual ? 0 : 1);
})().catch((e) => {
  console.error("ERRO", e.message || e);
  process.exit(1);
});

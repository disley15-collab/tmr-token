// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// TRC-20 enxuto: endereço escolhido (CREATE2) + ajustes futuros pelo dono.
///
/// - Supply inicial criado na publicação, para a carteira do dono.
/// - "Autoridade" de emissão: o dono pode criar mais até o `teto`, enquanto não
///   renunciar (`renunciarEmissao`, irreversível) — como a mint authority do Solana.
/// - Nome, símbolo e informações públicas (site, logo, redes sociais...) editáveis.
/// - Quem tem token pode queimar o próprio saldo.
/// - Sem oráculo: o preço vem do mercado (pools).
contract TokenSimples is ERC20, Ownable {
    uint256 public immutable teto;
    bool public emissaoRenunciada;
    string public contractURI; // ERC-7572: JSON com logo e links
    string internal nomeAtual;
    string internal simboloAtual;
    mapping(string chave => string valor) public info;
    string[] internal chaves;
    mapping(string chave => bool) internal temChave;

    event NomeESimboloDefinidos(string nome, string simbolo);
    event InfoDefinida(string chave, string valor);
    event ContractURIUpdated();
    event EmissaoRenunciada();

    error AcimaDoTeto(uint256 teto, uint256 depois);
    error EmissaoJaRenunciada();
    error ListasDeTamanhoDiferente();
    error TransferFromZeroSemAllowance();

    constructor(string memory _nome, string memory _simbolo, uint256 _supplyInicial, uint256 _teto, address _dono)
        ERC20(_nome, _simbolo)
        Ownable(_dono)
    {
        if (_supplyInicial > _teto) revert AcimaDoTeto(_teto, _supplyInicial);
        teto = _teto;
        if (_supplyInicial > 0) _mint(_dono, _supplyInicial);
    }

    // ------------------------------------------------------------ supply

    function emitir(address _para, uint256 _qtd) external onlyOwner {
        if (emissaoRenunciada) revert EmissaoJaRenunciada();
        uint256 depois = totalSupply() + _qtd;
        if (depois > teto) revert AcimaDoTeto(teto, depois);
        _mint(_para, _qtd);
    }

    function queimar(uint256 _qtd) external {
        _burn(msg.sender, _qtd);
    }

    /// Irreversível: ninguém mais cria tokens.
    function renunciarEmissao() external onlyOwner {
        emissaoRenunciada = true;
        emit EmissaoRenunciada();
    }

    // --------------------------------------------------------- metadados

    function name() public view override returns (string memory) {
        return bytes(nomeAtual).length > 0 ? nomeAtual : super.name();
    }

    function symbol() public view override returns (string memory) {
        return bytes(simboloAtual).length > 0 ? simboloAtual : super.symbol();
    }

    function definirNomeESimbolo(string calldata _nome, string calldata _simbolo) external onlyOwner {
        nomeAtual = _nome;
        simboloAtual = _simbolo;
        emit NomeESimboloDefinidos(_nome, _simbolo);
    }

    /// Grava várias informações de uma vez ("site", "logo", "x", "telegram"...).
    function definirInfos(string[] calldata _chaves, string[] calldata _valores) external onlyOwner {
        if (_chaves.length != _valores.length) revert ListasDeTamanhoDiferente();
        for (uint256 i; i < _chaves.length; i++) {
            if (!temChave[_chaves[i]]) {
                temChave[_chaves[i]] = true;
                chaves.push(_chaves[i]);
            }
            info[_chaves[i]] = _valores[i];
            emit InfoDefinida(_chaves[i], _valores[i]);
        }
    }

    function todasAsInfos() external view returns (string[] memory k, string[] memory v) {
        k = chaves;
        v = new string[](k.length);
        for (uint256 i; i < k.length; i++) v[i] = info[k[i]];
    }

    function setContractURI(string calldata _uri) external onlyOwner {
        contractURI = _uri;
        emit ContractURIUpdated();
    }

    // ------------------------------------------------------------- ERC20

    /// Bloqueia o Transfer falso de valor zero (sem a assinatura do dono do saldo).
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        if (value == 0 && from != msg.sender && allowance(from, msg.sender) == 0) revert TransferFromZeroSemAllowance();
        return super.transferFrom(from, to, value);
    }
}

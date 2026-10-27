// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { StdInvariant } from "forge-std/StdInvariant.sol";
import { TokenSimples } from "../src/TokenSimples.sol";

contract TokenSimplesTest is Test {
    address dono = makeAddr("dono");
    address bob = makeAddr("bob");
    TokenSimples t;

    function setUp() public {
        t = new TokenSimples("Provisorio", "PROV", 1_000e18, 10_000e18, dono);
    }

    function test_SupplyInicialNoDono() public view {
        assertEq(t.totalSupply(), 1_000e18);
        assertEq(t.balanceOf(dono), 1_000e18);
        assertEq(t.owner(), dono);
    }

    function test_EmissaoAteOTetoERenuncia() public {
        vm.prank(bob);
        vm.expectRevert();
        t.emitir(bob, 1);
        vm.prank(dono);
        t.emitir(bob, 9_000e18);
        vm.prank(dono);
        vm.expectRevert(abi.encodeWithSelector(TokenSimples.AcimaDoTeto.selector, 10_000e18, 10_000e18 + 1));
        t.emitir(bob, 1);
        vm.prank(bob);
        t.queimar(500e18);
        vm.startPrank(dono);
        t.renunciarEmissao();
        vm.expectRevert(TokenSimples.EmissaoJaRenunciada.selector);
        t.emitir(dono, 1);
        vm.stopPrank();
    }

    function test_MetadadosEditaveisSoPeloDono() public {
        vm.prank(bob);
        vm.expectRevert();
        t.definirNomeESimbolo("X", "X");
        vm.prank(dono);
        t.definirNomeESimbolo("Nome Final", "FIN");
        assertEq(t.name(), "Nome Final");
        assertEq(t.symbol(), "FIN");
        string[] memory k = new string[](2);
        string[] memory v = new string[](2);
        (k[0], k[1]) = ("site", "x");
        (v[0], v[1]) = ("https://exemplo.com", "@exemplo");
        vm.prank(dono);
        t.definirInfos(k, v);
        (string[] memory tk, string[] memory tv) = t.todasAsInfos();
        assertEq(tk.length, 2);
        assertEq(tv[1], "@exemplo");
        vm.prank(dono);
        t.setContractURI("ipfs://x");
        assertEq(t.contractURI(), "ipfs://x");
    }

    function test_SupplyInicialAcimaDoTetoReverte() public {
        vm.expectRevert(abi.encodeWithSelector(TokenSimples.AcimaDoTeto.selector, 1, 2));
        new TokenSimples("X", "X", 2, 1, dono);
    }

    function test_TransferFromZeroSemAllowance() public {
        vm.prank(bob);
        vm.expectRevert(TokenSimples.TransferFromZeroSemAllowance.selector);
        t.transferFrom(dono, bob, 0);
    }

    function test_QueimaSoDoProprioSaldo() public {
        vm.prank(dono);
        t.transfer(bob, 100e18);
        vm.prank(bob);
        t.queimar(40e18);
        assertEq(t.balanceOf(bob), 60e18, "saiu de quem queimou");
        assertEq(t.balanceOf(dono), 900e18, "saldo do dono intacto");
        assertEq(t.totalSupply(), 960e18);
        vm.prank(bob);
        vm.expectRevert();
        t.queimar(61e18); // mais do que tem
    }

    // ------------------------------------------------------------- fuzz

    function testFuzz_EmissaoNuncaPassaOTeto(uint256 a, uint256 b) public {
        a = bound(a, 0, 20_000e18);
        b = bound(b, 0, 20_000e18);
        vm.startPrank(dono);
        try t.emitir(bob, a) {} catch {}
        try t.emitir(bob, b) {} catch {}
        vm.stopPrank();
        assertLe(t.totalSupply(), t.teto());
    }

    function testFuzz_TransferenciaConservaSupply(uint256 q, address para) public {
        vm.assume(para != address(0));
        q = bound(q, 0, 1_000e18);
        uint256 antes = t.totalSupply();
        vm.prank(dono);
        t.transfer(para, q);
        assertEq(t.totalSupply(), antes);
        if (para != dono) assertEq(t.balanceOf(dono), 1_000e18 - q);
    }

    function testFuzz_SoODonoEditaEEmite(address quem) public {
        vm.assume(quem != dono);
        string[] memory k = new string[](1);
        string[] memory v = new string[](1);
        vm.startPrank(quem);
        vm.expectRevert();
        t.emitir(quem, 1);
        vm.expectRevert();
        t.definirNomeESimbolo("a", "b");
        vm.expectRevert();
        t.definirInfos(k, v);
        vm.expectRevert();
        t.setContractURI("x");
        vm.expectRevert();
        t.renunciarEmissao();
        vm.stopPrank();
    }

    function test_ParametrosDaMainnet() public {
        TokenSimples m = new TokenSimples("Token Multirrede", "TMR", 1_000_000_000e18, 18_446_744_073_709_551_615 * 1e12, dono);
        assertEq(m.totalSupply(), 1_000_000_000e18);
        assertEq(m.teto() / 1e12, type(uint64).max);
        assertEq(m.decimals(), 18);
        uint256 falta = m.teto() - m.totalSupply();
        vm.prank(dono);
        m.emitir(dono, falta); // até o teto exato cabe
        assertEq(m.totalSupply(), m.teto());
    }
}

/// Invariantes com chamadas aleatórias de vários atores.
contract Operador is Test {
    TokenSimples public t;
    address public dono;
    address[3] public atores;

    constructor(TokenSimples _t, address _dono) {
        t = _t;
        dono = _dono;
        atores = [makeAddr("a1"), makeAddr("a2"), makeAddr("a3")];
    }

    function emitir(uint256 i, uint256 q) external {
        q = bound(q, 0, 5_000e18);
        vm.prank(dono);
        try t.emitir(atores[i % 3], q) {} catch {}
    }

    function transferir(uint256 i, uint256 j, uint256 q) external {
        address de = i % 4 == 3 ? dono : atores[i % 3];
        q = bound(q, 0, t.balanceOf(de));
        vm.prank(de);
        t.transfer(atores[j % 3], q);
    }

    function queimar(uint256 i, uint256 q) external {
        address de = atores[i % 3];
        q = bound(q, 0, t.balanceOf(de));
        vm.prank(de);
        t.queimar(q);
    }

    function renunciar() external {
        vm.prank(dono);
        t.renunciarEmissao();
    }
}

contract TokenSimplesInvariantes is StdInvariant, Test {
    TokenSimples t;
    Operador op;
    address dono = makeAddr("dono");

    function setUp() public {
        t = new TokenSimples("P", "P", 1_000e18, 10_000e18, dono);
        op = new Operador(t, dono);
        targetContract(address(op));
    }

    function invariant_SupplyNuncaPassaOTeto() public view {
        assertLe(t.totalSupply(), t.teto());
    }

    function invariant_SomaDosSaldosIgualAoSupply() public view {
        uint256 soma = t.balanceOf(dono);
        for (uint256 i; i < 3; i++) soma += t.balanceOf(op.atores(i));
        assertEq(soma, t.totalSupply());
    }
}

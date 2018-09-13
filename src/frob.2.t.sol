pragma solidity ^0.4.24;

import "ds-test/test.sol";
import "ds-token/token.sol";

import {Vat2, VatI} from './tune.2.sol';
import {Pit, PitI} from './frob.2.sol';
import {Cat, CatI} from './bite.2.sol';
import {Vow, VowI} from './heal.2.sol';
import {Drip2, DripI} from './drip.2.sol';
import {Dai20} from './transferFrom.sol';
import {GemJoin, GemJoinI, ETHJoin, ETHJoinI, DaiJoin, DaiJoinI} from './join.2.sol';
import {GemMove, DaiMove} from './move.sol';

import {WarpFlip as Flipper} from './flip.t.sol';
import {WarpFlop as Flopper} from './flop.t.sol';
import {WarpFlap as Flapper} from './flap.t.sol';


// interfaces can't inherit :|
contract WarpVatI is VatI {
    function era() external returns (uint48 _era);
    function mint(address guy, uint256 wad) external;
}

contract WarpVat is Vat2 {
    uint48 _era; function warp(uint48 era_) public { _era = era_; }
    function era() public view returns (uint48) { return _era; }

    int256 constant ONE = 10 ** 27;
    function mint(address guy, uint256 wad) public {
      assembly {
        function hash2(b, i) -> h {
          mstore(0, i)
          mstore(32, b)
          h := keccak256(0, 64)
        }
        let hash_0 := hash2(4, calldataload(4))

        // set dai[guy] += wad * ONE
        sstore(hash_0, add(sload(hash_0), mul(calldataload(36), 1000000000000000000000000000)))

        // set debt += wad * ONE
        sstore(5, add(sload(5), mul(calldataload(36), 1000000000000000000000000000)))
      }
    }
}

contract WarpVowI is VowI {}

contract WarpVow is Vow {}

contract Frob2Test is DSTest {
    WarpVatI  vat;
    PitI      pit;
    Dai20     dai;
    DSToken  gold;
    DripI    drip;

    GemJoinI gemA;

    function try_frob(bytes32 ilk, int ink, int art) public returns(bool) {
        bytes4 sig = bytes4(keccak256("frob(bytes32,int256,int256)"));
        return address(pit).call(sig, ilk, ink, art);
    }

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function setUp() public {
        vat = WarpVatI(new WarpVat());
        pit = PitI(new Pit(vat));
        dai = new Dai20(vat);

        gold = new DSToken("GEM");
        gold.mint(1000 ether);

        vat.init("gold");
        gemA = GemJoinI(new GemJoin(vat, "gold", gold));

        pit.file("gold", "spot", ray(1 ether));
        pit.file("gold", "line", 1000 ether);
        pit.file("Line", uint(1000 ether));
        drip = DripI(new Drip2(vat));
        drip.init("gold");
        vat.rely(drip);
        pit.file("drip", drip);

        gold.approve(gemA);
        gold.approve(vat);

        vat.rely(pit);
        vat.rely(dai);
        vat.rely(gemA);

        gemA.join(bytes32(address(this)), 1000 ether);
    }

    function gem(bytes32 ilk, address urn) internal view returns (uint) {
        return vat.gem(ilk, bytes32(urn)) / 10 ** 27;
    }
    function ink(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, bytes32(urn)); art_;
        return ink_;
    }
    function art(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, bytes32(urn)); ink_;
        return art_;
    }


    function test_join() public {
        gold.mint(500 ether);
        assertEq(gold.balanceOf(this),       500 ether);
        assertEq(gold.balanceOf(gemA),   1000 ether);
        gemA.join(bytes32(address(this)), 500 ether);
        assertEq(gold.balanceOf(this),         0 ether);
        assertEq(gold.balanceOf(gemA),   1500 ether);
        gemA.exit(this, 250 ether);
        assertEq(gold.balanceOf(this),       250 ether);
        assertEq(gold.balanceOf(gemA),   1250 ether);
    }
    function test_lock() public {
        assertEq(ink("gold", this),    0 ether);
        assertEq(gem("gold", this), 1000 ether);
        pit.frob("gold", 6 ether, 0);
        assertEq(ink("gold", this),   6 ether);
        assertEq(gem("gold", this), 994 ether);
        pit.frob("gold", -6 ether, 0);
        assertEq(ink("gold", this),    0 ether);
        assertEq(gem("gold", this), 1000 ether);
    }
    function test_calm() public {
        // calm means that the debt ceiling is not exceeded
        // it's ok to increase debt as long as you remain calm
        pit.file("gold", 'line', 10 ether);
        assertTrue( try_frob("gold", 10 ether, 9 ether));
        // only if under debt ceiling
        assertTrue(!try_frob("gold",  0 ether, 2 ether));
    }
    function test_cool() public {
        // cool means that the debt has decreased
        // it's ok to be over the debt ceiling as long as you're cool
        pit.file("gold", 'line', 10 ether);
        assertTrue(try_frob("gold", 10 ether,  8 ether));
        pit.file("gold", 'line', 5 ether);
        // can decrease debt when over ceiling
        assertTrue(try_frob("gold",  0 ether, -1 ether));
    }
    function test_safe() public {
        // safe means that the cdp is not risky
        // you can't frob a cdp into unsafe
        pit.frob("gold", 10 ether, 5 ether);                // safe draw
        assertTrue(!try_frob("gold", 0 ether, 6 ether));  // unsafe draw
    }
    function test_nice() public {
        // nice means that the collateral has increased or the debt has
        // decreased. remaining unsafe is ok as long as you're nice

        pit.frob("gold", 10 ether, 10 ether);
        pit.file("gold", 'spot', ray(0.5 ether));  // now unsafe

        // debt can't increase if unsafe
        assertTrue(!try_frob("gold",  0 ether,  1 ether));
        // debt can decrease
        assertTrue( try_frob("gold",  0 ether, -1 ether));
        // ink can't decrease
        assertTrue(!try_frob("gold", -1 ether,  0 ether));
        // ink can increase
        assertTrue( try_frob("gold",  1 ether,  0 ether));

        // cdp is still unsafe
        // ink can't decrease, even if debt decreases more
        assertTrue(!this.try_frob("gold", -2 ether, -4 ether));
        // debt can't increase, even if ink increases more
        assertTrue(!this.try_frob("gold",  5 ether,  1 ether));

        // ink can decrease if end state is safe
        assertTrue( this.try_frob("gold", -1 ether, -4 ether));
        pit.file("gold", 'spot', ray(0.4 ether));  // now unsafe
        // debt can increase if end state is safe
        assertTrue( this.try_frob("gold",  5 ether, 1 ether));
    }
}

contract Join2Test is DSTest {
    WarpVatI   vat;
    ETHJoinI  ethA;
    DaiJoinI  daiA;
    DSToken    dai;
    bytes32     me;

    function setUp() public {
        vat = WarpVatI(new WarpVat());
        vat.init("eth");

        ethA = ETHJoinI(new ETHJoin(vat, "eth"));
        vat.rely(ethA);

        dai  = new DSToken("Dai");
        daiA = DaiJoinI(new DaiJoin(vat, dai));
        vat.rely(daiA);
        dai.setOwner(daiA);

        me = bytes32(address(this));
    }
    function () external payable {}
    function test_eth_join() public {
        ethA.join.value(10 ether)(bytes32(address(this)));
        assertEq(vat.gem("eth", me), rad(10 ether));
    }
    function test_eth_exit() public {
        ethA.join.value(50 ether)(bytes32(address(this)));
        ethA.exit(this, 10 ether);
        assertEq(vat.gem("eth", me), rad(40 ether));
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }
    function test_dai_exit() public {
        vat.mint(address(me), 100 ether);
        daiA.exit(this, 60 ether);
        assertEq(dai.balanceOf(address(me)), 60 ether);
        assertEq(vat.dai(me),            rad(40 ether));
    }
    function test_dai_exit_join() public {
        vat.mint(address(me), 100 ether);
        daiA.exit(this, 60 ether);
        dai.approve(daiA, uint(-1));
        daiA.join(bytes32(address(this)), 30 ether);
        assertEq(dai.balanceOf(address(me)), 30 ether);
        assertEq(vat.dai(me),            rad(70 ether));
    }
}

contract Bite2Test is DSTest {
    WarpVatI vat;
    PitI     pit;
    VowI     vow;
    CatI     cat;
    Dai20    dai;
    DSToken gold;
    DripI   drip;

    GemJoinI gemA;
    GemMove  gemM;
    DaiMove  daiM;

    Flipper flip;
    Flopper flop;
    Flapper flap;

    DSToken gov;

    function try_frob(bytes32 ilk, int ink, int art) public returns(bool) {
        bytes4 sig = bytes4(keccak256("frob(bytes32,int256,int256)"));
        return address(vat).call(sig, ilk, ink, art);
    }

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }

    function gem(bytes32 ilk, address urn) internal view returns (uint) {
        return vat.gem(ilk, bytes32(urn)) / 10 ** 27;
    }
    function ink(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, bytes32(urn)); art_;
        return ink_;
    }
    function art(bytes32 ilk, address urn) internal view returns (uint) {
        (uint ink_, uint art_) = vat.urns(ilk, bytes32(urn)); ink_;
        return art_;
    }

    function setUp() public {
        gov = new DSToken('GOV');
        gov.mint(100 ether);

        vat = WarpVatI(new WarpVat());
        pit = PitI(new Pit(vat));
        vat.rely(pit);
        dai = new Dai20(vat);
        vat.rely(dai);

        daiM = new DaiMove(vat);
        vat.rely(daiM);

        flap = new Flapper(daiM, gov);
        flop = new Flopper(daiM, gov);
        gov.setOwner(flop);

        vow = VowI(new Vow());
        vow.file("vat", address(vat));
        vow.file("flap", address(flap));
        vow.file("flop", address(flop));
        flop.rely(vow);


        drip = DripI(new Drip2(vat));
        drip.init("gold");
        drip.file("vow", bytes32(address(vow)));
        vat.rely(drip);
        pit.file("drip", drip);

        cat = CatI(new Cat(vat));
        cat.file("pit", pit);
        cat.file("vow", vow);
        vat.rely(cat);
        vow.rely(cat);

        gold = new DSToken("GEM");
        gold.mint(1000 ether);

        vat.init("gold");
        gemA = GemJoinI(new GemJoin(vat, "gold", gold));
        vat.rely(gemA);
        gold.approve(gemA);
        gemA.join(bytes32(address(this)), 1000 ether);

        gemM = new GemMove(vat, "gold");
        vat.rely(gemM);

        pit.file("gold", "spot", ray(1 ether));
        pit.file("gold", "line", 1000 ether);
        pit.file("Line", uint(1000 ether));
        flip = new Flipper(daiM, gemM);
        cat.file("gold", "flip", flip);
        cat.file("gold", "chop", ray(1 ether));

        vat.rely(flip);
        vat.rely(flap);
        vat.rely(flop);

        daiM.hope(flip);
        daiM.hope(flop);
        gold.approve(vat);
        gov.approve(flap);
    }
    function test_happy_bite() public {
        // spot = tag / (par . mat)
        // tag=5, mat=2
        pit.file("gold", 'spot', ray(2.5 ether));
        pit.frob("gold",  40 ether, 100 ether);

        // tag=4, mat=2
        pit.file("gold", 'spot', ray(2 ether));  // now unsafe

        assertEq(ink("gold", this),  40 ether);
        assertEq(art("gold", this), 100 ether);
        assertEq(vow.Woe(), 0 ether);
        assertEq(gem("gold", this), 960 ether);
        uint id = cat.bite("gold", bytes32(address(this)));
        assertEq(ink("gold", this), 0);
        assertEq(art("gold", this), 0);
        assertEq(vow.sin(vow.era()), 100 ether);
        assertEq(gem("gold", this), 960 ether);

        cat.file("gold", "lump", uint(100 ether));
        uint auction = cat.flip(id, 100 ether);  // flip all the tab

        assertEq(dai.balanceOf(vow),   0 ether);
        flip.tend(auction, 40 ether,   1 ether);
        assertEq(dai.balanceOf(vow),   1 ether);
        flip.tend(auction, 40 ether, 100 ether);
        assertEq(dai.balanceOf(vow), 100 ether);

        assertEq(dai.balanceOf(this),       0 ether);
        assertEq(gem("gold", this), 960 ether);
        vat.mint(this, 100 ether);  // magic up some dai for bidding
        flip.dent(auction, 38 ether,  100 ether);
        assertEq(dai.balanceOf(this), 100 ether);
        assertEq(dai.balanceOf(vow),  100 ether);
        assertEq(gem("gold", this), 962 ether);
        assertEq(gem("gold", this), 962 ether);

        assertEq(vow.sin(vow.era()), 100 ether);
        assertEq(dai.balanceOf(vow), 100 ether);
    }

    function test_floppy_bite() public {
        pit.file("gold", 'spot', ray(2.5 ether));
        pit.frob("gold",  40 ether, 100 ether);
        pit.file("gold", 'spot', ray(2 ether));  // now unsafe

        assertEq(vow.sin(vow.era()),   0 ether);
        cat.bite("gold", bytes32(address(this)));
        assertEq(vow.sin(vow.era()), 100 ether);

        assertEq(vow.Sin(), 100 ether);
        vow.flog(vow.era());
        assertEq(vow.Sin(),   0 ether);
        assertEq(vow.Woe(), 100 ether);
        assertEq(vow.Joy(),   0 ether);
        assertEq(vow.Ash(),   0 ether);

        vow.file("sump", uint(10 ether));
        uint f1 = vow.flop();
        assertEq(vow.Woe(),  90 ether);
        assertEq(vow.Joy(),   0 ether);
        assertEq(vow.Ash(),  10 ether);
        flop.dent(f1, 1000 ether, 10 ether);
        assertEq(vow.Woe(),  90 ether);
        assertEq(vow.Joy(),  10 ether);
        assertEq(vow.Ash(),  10 ether);

        assertEq(gov.balanceOf(this),  100 ether);
        flop.warp(4 hours);
        flop.deal(f1);
        assertEq(gov.balanceOf(this), 1100 ether);
    }

    function test_flappy_bite() public {
        // get some surplus
        vat.mint(vow, 100 ether);
        assertEq(dai.balanceOf(vow),  100 ether);
        assertEq(gov.balanceOf(this), 100 ether);

        vow.file("bump", uint(100 ether));
        assertEq(vow.Awe(), 0 ether);
        uint id = vow.flap();

        assertEq(dai.balanceOf(this),   0 ether);
        assertEq(gov.balanceOf(this), 100 ether);
        flap.tend(id, 100 ether, 10 ether);
        flap.warp(4 hours);
        flap.deal(id);
        assertEq(dai.balanceOf(this),   100 ether);
        assertEq(gov.balanceOf(this),    90 ether);
    }
}

contract Fold2Test is DSTest {
    VatI vat;

    function ray(uint wad) internal pure returns (uint) {
        return wad * 10 ** 9;
    }
    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }
    function tab(bytes32 ilk, bytes32 urn) internal view returns (uint) {
        (uint ink, uint art)  = vat.urns(ilk, urn); ink;
        (uint take, uint rate, uint Ink, uint Art) = vat.ilks(ilk); Art; Ink; take;
        return art * rate;
    }
    function jam(bytes32 ilk, bytes32 urn) internal view returns (uint) {
        (uint ink, uint art)  = vat.urns(ilk, urn); art;
        (uint take, uint rate, uint Ink, uint Art) = vat.ilks(ilk); Art; Ink; rate;
        return ink * take;
    }

    function setUp() public {
        vat = VatI(new Vat2());
        vat.init("gold");
    }
    function test_fold() public {
        vat.tune("gold", "bob", "bob", "bob", 0, 1 ether);

        assertEq(tab("gold", "bob"), rad(1.00 ether));
        vat.fold("gold", "ali",  int(ray(0.05 ether)));
        assertEq(tab("gold", "bob"), rad(1.05 ether));
        assertEq(vat.dai("ali"),     rad(0.05 ether));
    }
    function test_toll_down() public {
        vat.slip("gold", "bob", int(rad(1 ether)));
        vat.slip("gold", "cat", int(rad(2 ether)));
        vat.tune("gold", "bob", "bob", "bob", 1 ether, 0);
        vat.tune("gold", "cat", "cat", "cat", 2 ether, 0);

        assertEq(jam("gold", "bob"),     rad(1.00 ether));
        assertEq(jam("gold", "cat"),     rad(2.00 ether));
        vat.toll("gold", "ali",     -int(ray(0.05 ether)));
        assertEq(jam("gold", "bob"),     rad(0.95 ether));
        assertEq(jam("gold", "cat"),     rad(1.90 ether));
        assertEq(vat.gem("gold", "ali"), rad(0.15 ether));
    }
    function test_toll_up() public {
        vat.slip("gold", "ali", int(rad(1 ether)));
        vat.slip("gold", "bob", int(rad(1 ether)));
        vat.slip("gold", "cat", int(rad(2 ether)));
        vat.tune("gold", "bob", "bob", "bob", 1 ether, 0);
        vat.tune("gold", "cat", "cat", "cat", 2 ether, 0);

        assertEq(jam("gold", "bob"),     rad(1.00 ether));
        assertEq(jam("gold", "cat"),     rad(2.00 ether));
        vat.toll("gold", "ali",      int(ray(0.05 ether)));
        assertEq(jam("gold", "bob"),     rad(1.05 ether));
        assertEq(jam("gold", "cat"),     rad(2.10 ether));
        assertEq(vat.gem("gold", "ali"), rad(0.85 ether));
    }
}

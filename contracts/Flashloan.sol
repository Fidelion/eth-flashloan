// SPDX-License-Identifier: MIT
pragma solidity ^0.5.0;
pragma experimental ABIEncoderV2;

import "@studydef/money-legos/dydx/contracts/DydxFlashloanBase.sol";
import "@studydef/money-legos/dydx/contracts/ICallee.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./IUniswapV2Router02.sol";
import "./IWeth";
import { KyberNetworkProxy as IKyberNetworkProxy } from '@studydefi/money-legos/kyber/contracts/KyberNetworkProxy.sol';

contract Flashloan is ICallee, DydxFlashloanBase {
    enum Direction { KyberToUniswap, UniswapToKyber }

    struct ArbInfo {
        Direction direction;
        uint256 repayAmount;
    }

    event NewArbitrage {
        Direction direction,
        uint profit,
        uint date
    }

    IKyberNetworkProxy kyber;
    IUniswapV2Router02 uniswap;
    IWeth weth;
    IERC20 dai;
    address beneficiary;
    address constant KYBER_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    constructor(
        address kyberAddress,
        address uniswapAddress,
        address wethAddress,
        address daiAddress,
        address beneficiaryAddress
    ) {
        kyber = IKyberNetworkProxy(kyberAddress);
        uniswap = IUniswapV2Router02(uniswapAddress);
        weth = IWeth(wethAddress);
        dai = IERC20(daiAddress);
        beneficiary = beneficiaryAddress;
    }

    function callFunction(
        address sender,
        Account.Info memory account,
        bytes memory data
    ) public {
        ArbInfo memory arbInfo = abi.decode(data, (ArbInfo));
        uint256 balanceDai = dai.balanceOf(address(this));

        if(arbInfo == Direction.KyberToUniswap) {
            // Buy Ether on Kyber
            dai.approve(address(kyber), balanceDai);
            (uint expectedRate, ) = kyber.getExpectedRate(
                dai,
                IERC20(KYBER_ETH_ADDRESS),
                balanceDai
            );

            kyber.swapTokenToEther(dai, balanceDai, expectedRate);

            // Sell Ether on Uniswap
            address[] memory path = new address[](2);
            path[0] = address(weth);
            path[1] = address(dai);
            uint[] memory minOuts = uniswap.getAmountOut(address(this).balance, path);
            uniswap.swapExactETHForTokens.value(address(this).balance)(
                minOuts[1],
                path,
                address(this),
                now
            );
        } else {
            // Buy Ether on Uniswap
            dai.approve(address(uniswap), balanceDai);

            address[] memory path = new address[](2);
            path[0] = address(dai);
            path[1] = address(weth);
            uint[] memory minOuts = uniswap.getAmountOut(balanceDai, path);
            uniswap.swapExactTokensForETH.value(
                balanceDai,
                minOuts[1],
                path,
                address(this),
                now
            );

            // Sell Ether on Kyber
            (uint expectedRate, ) = kyber.getExpectedRate(
                IERC20(KYBER_ETH_ADDRESS),
                dai,
                address(this).balance
            );

            kyber.swapEtherToToken.value(address(this).balance)(
                dai, 
                expectedRate
            );
        }
        // Note that you can ignore the line below
        // if your dydx account (this contract in this case)
        // has deposited at least ~2 Wei of assets into the account
        // to balance out the collaterization ratio
        require(
            dai.balanceOf(address(this)) >= arbInfo.repayAmount,
            "Not enough funds to repay dydx loan!"
        );

        uint profit = dai.balanceOf(address(this)) - arbInfo.repayAmount;
        dai.transfer(beneficiary, profit);
        emit NewArbitrage(arbInfo.direction, profit, now);
    }

    // Fallback function
    function() external payable {}

    function initiateFlashloan(
        address _solo, 
        address _token, 
        uint256 _amount,
        Direction _direction
    ) external {
        ISoloMargin solo = ISoloMargin(_solo);

        // Get marketId from token address
        uint256 marketId = _getMarketIdFromTokenAddress(_solo, _token);

        // Repay calculation
        uint256 repayAmount = _getRepaymentAmountInternal(_amount);
        IERC20(_token).approve(_solo, repayAmount);

        // 1. Withdraw
        // 2. Call callFunction()
        // 3. Deposit back
        Actions.ActionArgs[] memory operations = new Actions.ActionArgs[](3);

        operations[0] = _getWithdrawAction(marketId, _amount);
        operations[1] = _getCallAction(
            // Encode MyCustomData for callFunction
            abi.encode(ArbInfo({ direction: _direction, repayAmount: repayAmount }))
        );

        operations[2] = _getDepositAction(marketId, repayAmount);

        Account.Info[] memory accountInfos = new Account.info[](1);
        accountInfos[0] = _getAccountInfo();

        solo.operate(accountInfos, operations);
    }
}

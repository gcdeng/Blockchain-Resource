// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

import "hardhat/console.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    using SafeMath for uint256;

    address public tokenA;
    address public tokenB;
    uint256 private reserveA; // uses single storage slot, accessible via getReserves
    uint256 private reserveB; // uses single storage slot, accessible via getReserves
    uint256 public kLast; // reserveA * reserveB, as of immediately after the most recent liquidity event

    constructor(address _tokenA, address _tokenB) ERC20("SimpleSwap LP Token", "SLP") {
        require(Address.isContract(_tokenA), "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(Address.isContract(_tokenB), "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        tokenA = _tokenA;
        tokenB = _tokenB;
    }

    function _updateReserves() private {
        reserveA = ERC20(tokenA).balanceOf(address(this));
        reserveB = ERC20(tokenB).balanceOf(address(this));
    }

    // Implement core logic here
    /// @notice Swap tokenIn for tokenOut with amountIn
    /// @param tokenIn The address of the token to swap from
    /// @param tokenOut The address of the token to swap to
    /// @param amountIn The amount of tokenIn to swap
    /// @return amountOut The amount of tokenOut received
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external override returns (uint256 amountOut) {
        // check tokenIn & tokenOut
        if (tokenIn != tokenA && tokenIn != tokenB) {
            revert("SimpleSwap: INVALID_TOKEN_IN");
        }
        if (tokenOut != tokenA && tokenOut != tokenB) {
            revert("SimpleSwap: INVALID_TOKEN_OUT");
        }
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");

        // check amount
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // calculate amountOut
        uint256 reserveTokenIn = ERC20(tokenIn).balanceOf(address(this));
        uint256 reserveTokenOut = ERC20(tokenOut).balanceOf(address(this));
        // X * Y = K -> (reserveTokenIn + amountIn) * (reserveTokenOut - amountOut) = kLast
        amountOut = reserveTokenOut.sub(kLast.div(reserveTokenIn.add(amountIn)));
        // check amountOut
        require(amountOut > 0, "SimpleSwap: INSUFFICIENT_OUTPUT_AMOUNT");

        // get tokenIn from taker
        ERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);

        // transfer tokenOut to taker
        ERC20(tokenOut).transfer(msg.sender, amountOut);

        // update reserves
        _updateReserves();

        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
    }

    /// @notice Add liquidity to the pool
    /// @param amountAIn The amount of tokenA to add
    /// @param amountBIn The amount of tokenB to add
    /// @return amountA The actually amount of tokenA added
    /// @return amountB The actually amount of tokenB added
    /// @return liquidity The amount of liquidity minted
    function addLiquidity(uint256 amountAIn, uint256 amountBIn)
        external
        override
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        )
    {
        require(amountAIn > 0 && amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // get total supply amount of LP token
        uint256 totalSupply = totalSupply();

        // calculate liquidity and actually amount of token added
        if (totalSupply == 0) {
            liquidity = Math.sqrt(amountAIn.mul(amountBIn));
            amountA = amountAIn;
            amountB = amountBIn;
        } else {
            liquidity = Math.min((amountAIn.mul(totalSupply)) / reserveA, (amountBIn.mul(totalSupply)) / reserveB);
            amountA = (liquidity.mul(reserveA)) / totalSupply;
            amountB = (liquidity.mul(reserveB)) / totalSupply;
        }

        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_MINTED");

        reserveA += amountA;
        reserveB += amountB;
        kLast = reserveA.mul(reserveB);

        ERC20(tokenA).transferFrom(msg.sender, address(this), amountA);
        ERC20(tokenB).transferFrom(msg.sender, address(this), amountB);
        _mint(msg.sender, liquidity); // mint LP token to maker

        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Remove liquidity from the pool
    /// @param liquidity The amount of liquidity to remove
    /// @return amountA The amount of tokenA received
    /// @return amountB The amount of tokenB received
    function removeLiquidity(uint256 liquidity) external override returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");

        uint256 totalSupply = totalSupply();

        // calculate amount of token pair
        amountA = (liquidity.mul(reserveA)).div(totalSupply);
        amountB = (liquidity.mul(reserveB)).div(totalSupply);

        reserveA -= amountA;
        reserveB -= amountB;
        kLast = reserveA.mul(reserveB);

        // transfer token pair to maker
        ERC20(tokenA).transfer(msg.sender, amountA);
        ERC20(tokenB).transfer(msg.sender, amountB);

        // transfer LP token from maker to contract
        transfer(address(this), liquidity);

        // burn LP token from contract
        _burn(address(this), liquidity);

        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
    }

    /// @notice Get the reserves of the pool
    /// @return reserveA The reserve of tokenA
    /// @return reserveB The reserve of tokenB
    function getReserves() external view override returns (uint256, uint256) {
        return (reserveA, reserveB);
    }

    /// @notice Get the address of tokenA
    /// @return tokenA The address of tokenA
    function getTokenA() external view override returns (address) {
        return tokenA;
    }

    /// @notice Get the address of tokenB
    /// @return tokenB The address of tokenB
    function getTokenB() external view override returns (address) {
        return tokenB;
    }
}

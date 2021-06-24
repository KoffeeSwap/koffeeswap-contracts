pragma solidity =0.6.6;

import './interfaces/IKoffeeSwapFactory.sol';
import './libraries/TransferHelper.sol';

import './interfaces/IKoffeeSwapRouter.sol';
import './libraries/KoffeeSwapLibrary.sol';
import './libraries/SafeMath.sol';
import './interfaces/IKRC20.sol';
import './interfaces/IWKCS.sol';

contract KoffeeSwapRouter is IKoffeeSwapRouter {
    using SafeMath for uint;

    address public immutable override factory;
    address public immutable override WKCS;

    modifier ensure(uint deadline) {
        require(deadline >= block.timestamp, 'KoffeeSwapRouter: EXPIRED');
        _;
    }

    constructor(address _factory, address _WKCS) public {
        factory = _factory;
        WKCS = _WKCS;
    }

    receive() external payable {
        assert(msg.sender == WKCS); // only accept KCS via fallback from the WKCS contract
    }

    // **** ADD LIQUIDITY ****
    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin
    ) internal virtual returns (uint amountA, uint amountB) {
        // create the pair if it doesn't exist yet
        if (IKoffeeSwapFactory(factory).getPair(tokenA, tokenB) == address(0)) {
            IKoffeeSwapFactory(factory).createPair(tokenA, tokenB);
        }
        (uint reserveA, uint reserveB) = KoffeeSwapLibrary.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint amountBOptimal = KoffeeSwapLibrary.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, 'KoffeeSwapRouter: INSUFFICIENT_B_AMOUNT');
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint amountAOptimal = KoffeeSwapLibrary.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, 'KoffeeSwapRouter: INSUFFICIENT_A_AMOUNT');
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint amountA, uint amountB, uint liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = KoffeeSwapLibrary.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = IKoffeeSwapPair(pair).mint(to);
    }
    function addLiquidityKCS(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline
    ) external virtual override payable ensure(deadline) returns (uint amountToken, uint amountKCS, uint liquidity) {
        (amountToken, amountKCS) = _addLiquidity(
            token,
            WKCS,
            amountTokenDesired,
            msg.value,
            amountTokenMin,
            amountKCSMin
        );
        address pair = KoffeeSwapLibrary.pairFor(factory, token, WKCS);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWKCS(WKCS).deposit{value: amountKCS}();
        assert(IWKCS(WKCS).transfer(pair, amountKCS));
        liquidity = IKoffeeSwapPair(pair).mint(to);
        // refund dust KCS, if any
        if (msg.value > amountKCS) TransferHelper.safeTransferKCS(msg.sender, msg.value - amountKCS);
    }

    // **** REMOVE LIQUIDITY ****
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountA, uint amountB) {
        address pair = KoffeeSwapLibrary.pairFor(factory, tokenA, tokenB);
        IKoffeeSwapPair(pair).transferFrom(msg.sender, pair, liquidity); // send liquidity to pair
        (uint amount0, uint amount1) = IKoffeeSwapPair(pair).burn(to);
        (address token0,) = KoffeeSwapLibrary.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, 'KoffeeSwapRouter: INSUFFICIENT_A_AMOUNT');
        require(amountB >= amountBMin, 'KoffeeSwapRouter: INSUFFICIENT_B_AMOUNT');
    }
    function removeLiquidityKCS(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountToken, uint amountKCS) {
        (amountToken, amountKCS) = removeLiquidity(
            token,
            WKCS,
            liquidity,
            amountTokenMin,
            amountKCSMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWKCS(WKCS).withdraw(amountKCS);
        TransferHelper.safeTransferKCS(to, amountKCS);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountA, uint amountB) {
        address pair = KoffeeSwapLibrary.pairFor(factory, tokenA, tokenB);
        uint value = approveMax ? uint(-1) : liquidity;
        IKoffeeSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }
    function removeLiquidityKCSWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountToken, uint amountKCS) {
        address pair = KoffeeSwapLibrary.pairFor(factory, token, WKCS);
        uint value = approveMax ? uint(-1) : liquidity;
        IKoffeeSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountKCS) = removeLiquidityKCS(token, liquidity, amountTokenMin, amountKCSMin, to, deadline);
    }

    // **** REMOVE LIQUIDITY (supporting fee-on-transfer tokens) ****
    function removeLiquidityKCSSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline
    ) public virtual override ensure(deadline) returns (uint amountKCS) {
        (, amountKCS) = removeLiquidity(
            token,
            WKCS,
            liquidity,
            amountTokenMin,
            amountKCSMin,
            address(this),
            deadline
        );
        TransferHelper.safeTransfer(token, to, IKRC20(token).balanceOf(address(this)));
        IWKCS(WKCS).withdraw(amountKCS);
        TransferHelper.safeTransferKCS(to, amountKCS);
    }
    function removeLiquidityKCSWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountKCSMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external virtual override returns (uint amountKCS) {
        address pair = KoffeeSwapLibrary.pairFor(factory, token, WKCS);
        uint value = approveMax ? uint(-1) : liquidity;
        IKoffeeSwapPair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountKCS = removeLiquidityKCSSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountKCSMin, to, deadline
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(uint[] memory amounts, address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = KoffeeSwapLibrary.sortTokens(input, output);
            uint amountOut = amounts[i + 1];
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOut) : (amountOut, uint(0));
            address to = i < path.length - 2 ? KoffeeSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            IKoffeeSwapPair(KoffeeSwapLibrary.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = KoffeeSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'KoffeeSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) returns (uint[] memory amounts) {
        amounts = KoffeeSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'KoffeeSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }
    function swapExactKCSForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WKCS, 'KoffeeSwapRouter: INVALID_PATH');
        amounts = KoffeeSwapLibrary.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'KoffeeSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWKCS(WKCS).deposit{value: amounts[0]}();
        assert(IWKCS(WKCS).transfer(KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
    }
    function swapTokensForExactKCS(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WKCS, 'KoffeeSwapRouter: INVALID_PATH');
        amounts = KoffeeSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, 'KoffeeSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWKCS(WKCS).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferKCS(to, amounts[amounts.length - 1]);
    }
    function swapExactTokensForKCS(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[path.length - 1] == WKCS, 'KoffeeSwapRouter: INVALID_PATH');
        amounts = KoffeeSwapLibrary.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, 'KoffeeSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWKCS(WKCS).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferKCS(to, amounts[amounts.length - 1]);
    }
    function swapKCSForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        virtual
        override
        payable
        ensure(deadline)
        returns (uint[] memory amounts)
    {
        require(path[0] == WKCS, 'KoffeeSwapRouter: INVALID_PATH');
        amounts = KoffeeSwapLibrary.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, 'KoffeeSwapRouter: EXCESSIVE_INPUT_AMOUNT');
        IWKCS(WKCS).deposit{value: amounts[0]}();
        assert(IWKCS(WKCS).transfer(KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amounts[0]));
        _swap(amounts, path, to);
        // refund dust KCS, if any
        if (msg.value > amounts[0]) TransferHelper.safeTransferKCS(msg.sender, msg.value - amounts[0]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal virtual {
        for (uint i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = KoffeeSwapLibrary.sortTokens(input, output);
            IKoffeeSwapPair pair = IKoffeeSwapPair(KoffeeSwapLibrary.pairFor(factory, input, output));
            uint amountInput;
            uint amountOutput;
            { // scope to avoid stack too deep errors
            (uint reserve0, uint reserve1,) = pair.getReserves();
            (uint reserveInput, uint reserveOutput) = input == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
            amountInput = IKRC20(input).balanceOf(address(pair)).sub(reserveInput);
            amountOutput = KoffeeSwapLibrary.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint amount0Out, uint amount1Out) = input == token0 ? (uint(0), amountOutput) : (amountOutput, uint(0));
            address to = i < path.length - 2 ? KoffeeSwapLibrary.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external virtual override ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        uint balanceBefore = IKRC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IKRC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'KoffeeSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactKCSForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        payable
        ensure(deadline)
    {
        require(path[0] == WKCS, 'KoffeeSwapRouter: INVALID_PATH');
        uint amountIn = msg.value;
        IWKCS(WKCS).deposit{value: amountIn}();
        assert(IWKCS(WKCS).transfer(KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amountIn));
        uint balanceBefore = IKRC20(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IKRC20(path[path.length - 1]).balanceOf(to).sub(balanceBefore) >= amountOutMin,
            'KoffeeSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT'
        );
    }
    function swapExactTokensForKCSSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    )
        external
        virtual
        override
        ensure(deadline)
    {
        require(path[path.length - 1] == WKCS, 'KoffeeSwapRouter: INVALID_PATH');
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, KoffeeSwapLibrary.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint amountOut = IKRC20(WKCS).balanceOf(address(this));
        require(amountOut >= amountOutMin, 'KoffeeSwapRouter: INSUFFICIENT_OUTPUT_AMOUNT');
        IWKCS(WKCS).withdraw(amountOut);
        TransferHelper.safeTransferKCS(to, amountOut);
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint amountA, uint reserveA, uint reserveB) public pure virtual override returns (uint amountB) {
        return KoffeeSwapLibrary.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountOut)
    {
        return KoffeeSwapLibrary.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut)
        public
        pure
        virtual
        override
        returns (uint amountIn)
    {
        return KoffeeSwapLibrary.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint amountIn, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return KoffeeSwapLibrary.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint amountOut, address[] memory path)
        public
        view
        virtual
        override
        returns (uint[] memory amounts)
    {
        return KoffeeSwapLibrary.getAmountsIn(factory, amountOut, path);
    }
}

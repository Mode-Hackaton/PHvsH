// SPDX-License-Identifier: MIT LICENSE

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "./IGame.sol";
import "./HODL.sol";
import "./ISeed.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";

contract Game is IGame, ERC721Enumerable, Ownable, Pausable {
    using Strings for uint256;
    uint256 public MAX_MINT = 100;
    uint256 public MAX_WL_MINT = 10;
    uint256 public WL_TIMER;

    // max number of nft
    uint256 public immutable MAX_TOKENS = 20000;
    // number of tokens in gen-0
    uint256 public PAID_TOKENS = 10000;
    // number of tokens minted
    uint16 public minted;
    // number of hodler minted
    uint256 public hodlerCount;
    // number of paperhand minted
    uint256 public PPCount;
    // base of price for minted over Gen-0
    uint256 public basePrice = 2000 ether;
    // price interval for minted over Gen-0
    uint256 public incrementedPrice = 500 ether;
    // root of merkleTree for WL
    bytes32 public merkleRoot;
    // state of mint for whitelisted
    bool public isWhiteListActive = false;
    // bool state for revealed nft
    bool public isRevealed = false;

    bool public transferPaused = false;
    // map for keep minted nft per WL address
    mapping(address => uint256) public whitelistedGen0;
    // mapping from tokenId to a struct containing the token's traits
    mapping(uint256 => TraitStruct) public tokenTraits;
    // reference to $HODL for burning on mint
    HODL public hodl;

    ISeed public randomSource;

    address public bank;
    address public treasuryLocked;

    string public currentBaseURI =
        "QmdGxe3gR9C3hU9LhLaVw3Ybk23C5QXcp6YggEenSt6E2c/";
    string public baseExtension = ".png";
    string public notRevealedUri =
        "QmaKpeUMjJLYdyiQ4efvhSnM79U8WmC828Z4hQ5tXKvms1/hidden.png";

    bool private _reentrant = false;

    address public multisigWallet = 0x0000000000000000000000000000000000000000;

    modifier nonReentrant() {
        require(!_reentrant, "No reentrancy");
        _reentrant = true;
        _;
        _reentrant = false;
    }

    /**
     * instantiates contract and rarity tables
     */
    constructor(HODL _hodl, address _treasury) ERC721("GAME", "Game") {
        treasuryLocked = _treasury;
        hodl = _hodl;
        Pausable._pause();
    }

    function setRandomSource(ISeed _seed) external onlyOwner {
        randomSource = _seed;
    }

    /***EXTERNAL */

    /**
     * mint a token - 95% Peper, 5% Hodler
     */
    function mintGenZero(uint256 amount)
        external
        payable
        nonReentrant
        whenNotPaused
    {
        require(tx.origin == _msgSender(), "Only EOA");
        require(amount > 0, "Invalid mint amount");
        require(
            minted + amount <= PAID_TOKENS,
            "All tokens on-sale already sold for Gen0"
        );
        require(amount * genZeroCost() == msg.value, "Invalid payment amount");

        uint256 seed;

        for (uint256 i = 0; i < amount; i++) {
            minted++;
            seed = random(minted);
            randomSource.update(minted ^ seed);
            generate(minted, seed);
            _safeMint(address(msg.sender), minted);
        }
    }

    /**
     * mint nft with $HODL token , 100% paperHand nft
     */
    function mint(uint256 amount) external nonReentrant whenNotPaused {
        require(tx.origin == _msgSender(), "Only EOA");
        require(amount > 0 && amount <= MAX_MINT, "Invalid mint amount");
        require(
            minted >= PAID_TOKENS && minted + amount <= MAX_TOKENS,
            "Invalid mint amount"
        );

        uint256 totalHodlCost = 0;

        for (uint256 i = 0; i < amount; i++) {
            totalHodlCost += calculateHodlCost();
        }
        hodl.transferFrom(_msgSender(), treasuryLocked, totalHodlCost);

        for (uint256 i = 0; i < amount; i++) {
            minted++;
            generate(minted, 0);
            _safeMint(address(msg.sender), minted);
        }
    }

    /**
     * mint nft with $HODL token , 100% paperHand nft
     */
    function mintPremium(uint256 amount) external onlyOwner {
        require(amount <= 10, "Invalid mint amount");
        TraitStruct memory t;
        t.isPP = false;
        t.remainingPower = 32000 ether;
        t.level = 10;

        for (uint256 i = 0; i < amount; i++) {
            minted++;
            generate(minted, 0);
            _safeMint(address(msg.sender), minted);
        }
    }

    /** Mint function only for whitelisted,
     *   available for first 10min at starting mint */

    function whiteListedMint(uint256 amount, bytes32[] memory _proof)
        external
        payable
        nonReentrant
    {
        // WL_Timer is here to lock access for WL only under 10min
        // it's setup by setWhitelistActive()
        require(
            (isWhiteListActive && WL_TIMER < block.timestamp),
            "whitelist is finish"
        );
        require(
            MerkleProof.verify(
                _proof,
                merkleRoot,
                bytes32(uint256(uint160(msg.sender)))
            ),
            "You'r not whitelisted !"
        );
        require(
            whitelistedGen0[msg.sender] + amount <= MAX_WL_MINT,
            "Only 2 Nfts by whitelisted address. "
        );

        require(minted + amount <= MAX_TOKENS, "All tokens minted");
        require(amount > 0 && amount <= MAX_MINT, "Invalid mint amount");
        require(amount * genZeroCost() == msg.value, "Invalid payment amount");

        uint256 seed;
        for (uint256 i = 0; i < amount; i++) {
            minted++;
            seed = random(minted);
            randomSource.update(minted ^ seed);
            generate(minted, seed);
            whitelistedGen0[msg.sender]++;
            _safeMint(address(msg.sender), minted);
        }
    }

    function genZeroCost() public view returns (uint256 price) {
        // Here set your price in ether by Gen-0 scale
        // All values in ether are to be modified before the launch
        if (minted <= 2000) return 80 * 10**18;
        else if (minted <= 3000) return 80 * 10**18;
        else if (minted <= 6000) return 80 * 10**18;
        else if (minted <= 9000) return 80 * 10**18;
        else if (minted <= 10000) return 80 * 10**18;
    }

    /**
     * determinate the hodl cost of minting,
     * this function is called only for mint of gen1 and more
     * @return the cost of the given token ID
     */
    function calculateHodlCost() public view returns (uint256) {
        require(minted >= PAID_TOKENS, "Gen1 not started");
        // this calculate relative price of supply minted after gen0
        uint256 gen = getGenPriceRank();
        uint256 price = (basePrice + (incrementedPrice * gen));
        return price;
    }

    function upgradeLevel(uint256 tokenId)
        external
        override
        returns (TraitStruct memory t)
    {
        require(msg.sender == address(bank));

        TraitStruct storage t = tokenTraits[tokenId];

        t.level = 6;

        return t;
    }

    function evolve(uint256 tokenId) external override {
        require(
            hodl.balanceOf(_msgSender()) >= 2000 ether &&
                _msgSender() == ownerOf(tokenId)
        );
        _switchToHodler(tokenId);
        hodl.transferFrom(_msgSender(), treasuryLocked, 2000 ether);
    }

    function evolveFromBank(uint256 tokenId) external {
        require(msg.sender == address(bank));

        _switchToHodler(tokenId);
    }

    function _switchToHodler(uint256 tokenId)
        internal
        returns (TraitStruct storage t)
    {
        TraitStruct storage t = tokenTraits[tokenId];

        t.isPP = false;

        return t;
    }

    function subRemainingPower(uint256 tokenId, uint256 withdraw)
        external
        override
        returns (TraitStruct memory t)
    {
        require(msg.sender == address(bank));

        TraitStruct storage t = tokenTraits[tokenId];

        t.remainingPower -= withdraw;

        return t;
    }

    /***INTERNAL */

    /**
     * generates traits for a specific token, checking to make sure it's unique
     * @param tokenId the id of the token to generate traits for
     * @param seed a pseudorandom 256 bit number to derive traits from
     * @return t - a struct of traits for the given token ID
     */
    function generate(uint256 tokenId, uint256 seed)
        internal
        returns (TraitStruct memory t)
    {
        if (minted <= PAID_TOKENS) t = randomMetadata(seed);
        else t = giveMetadata();
        tokenTraits[tokenId] = t;
        t.isPP ? PPCount++ : hodlerCount++;

        return t;
    }

    /**
     * selects the species and all of its traits based on the seed value
     * @param seed a pseudorandom 256 bit number to derive traits from
     * @return t -  a struct of randomly selected traits
     */
    function randomMetadata(uint256 seed)
        internal
        pure
        returns (TraitStruct memory t)
    {
        t.isPP = (seed & 0xFFFF) % 20 != 19;

        if (t.isPP) {
            t.remainingPower = 22000 ether;
            t.level = 1;
        } else {
            t.remainingPower = 22000 ether;
            t.level = 0;
        }
    }

    /**
     * selects the species and all of its traits based on the seed value
     * @return t -  a struct of randomly selected traits
     */
    function giveMetadata() internal pure returns (TraitStruct memory t) {
        t.isPP = true;
        t.remainingPower = 22000 ether;
        t.level = 0;
    }

    /**
     * generates a pseudorandom number
     * @param seed a value ensure different outcomes for different sources in the same block
     * @return a pseudorandom value
     */
    function random(uint256 seed) internal view returns (uint256) {
        console.log("Fetch New RANDOM with seed : ", seed);
        return
            uint256(
                keccak256(
                    abi.encodePacked(
                        tx.origin,
                        blockhash(block.number - 1),
                        block.timestamp,
                        seed
                    )
                )
            );
    }

    /***READ */

    function getTokenTraits(uint256 tokenId)
        public
        view
        override
        returns (TraitStruct memory)
    {
        return tokenTraits[tokenId];
    }

    function getPaidTokens() external view override returns (uint256) {
        return PAID_TOKENS;
    }

    function getGenPriceRank() public view returns (uint256 genCoef) {
        if (minted <= 11000) {
            return 0;
        } else if (minted <= 13000) {
            return 1;
        } else if (minted <= 15000) {
            return 2;
        } else if (minted <= 17000) {
            return 4;
        } else if (minted <= 20000) {
            return 6;
        }
    }

    /***ADMIN */

    /**
     * allows Multisig to withdraw funds from minting
     */
    function withdraw() external onlyOwner {
        multisigWallet.call{value: address(this).balance}("");
    }

    /**
    activ the reveal nft URI
     */
    function revealer() public onlyOwner {
        isRevealed = true;
    }

    /**
     * updates the number of tokens for sale
     */
    function setPaidTokens(uint256 _paidTokens) external onlyOwner {
        PAID_TOKENS = _paidTokens;
    }

    /**
     * enables owner to pause / unpause minting
     */
    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function setWhitelistActive(bool _wlEnd) external onlyOwner {
        WL_TIMER = block.timestamp + 1 days;
        isWhiteListActive = _wlEnd;
    }

    function setMerkleRoot(bytes32 root) public onlyOwner {
        merkleRoot = root;
    }

    function setBank(address _bank) public onlyOwner {
        bank = _bank;
    }

    function setTokenAddr(HODL _hodl) public onlyOwner {
        hodl = _hodl;
    }

    function walletOfOwner(address _owner)
        public
        view
        returns (uint256[] memory)
    {
        uint256 ownerTokenCount = balanceOf(_owner);
        uint256[] memory tokenIds = new uint256[](ownerTokenCount);
        for (uint256 i; i < ownerTokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokenIds;
    }

    function balanceHolder(address user)
        external
        view
        virtual
        override
        returns (uint256)
    {
        uint256 ownerTokenCount = balanceOf(user);
        return ownerTokenCount;
    }

    function _transfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        require(transferPaused == true, "transfer enable");
    }

    /***RENDER */

    function hasWhitelisted(bytes32[] calldata _merkleProof)
        public
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        return MerkleProof.verify(_merkleProof, merkleRoot, leaf);
    }

    //***  Utils **** */

    function compileAttributes(uint256 tokenId)
        public
        view
        returns (string memory)
    {
        IGame.TraitStruct memory s = getTokenTraits(tokenId);
        string memory traits;
        if (s.isPP) {
            traits = string(
                abi.encodePacked(
                    '[{"trait_type":"Class"',
                    ",",
                    '"value":"PaperHand"',
                    "},",
                    '{"trait_type": "Remaining power"',
                    ",",
                    '"value":"',
                    Strings.toString(s.remainingPower),
                    '"},',
                    '{"trait_type": "Level"',
                    ",",
                    '"value":"',
                    Strings.toString(s.level),
                    '"}]'
                )
            );
        } else {
            traits = string(
                abi.encode(
                    '[{"trait_type":"Class"',
                    ",",
                    '"value":"Holder"',
                    "}"
                )
            );
        }
        return traits;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override
        returns (string memory)
    {
        if (isRevealed == false) {
            return notRevealedUri;
        }

        IGame.TraitStruct memory s = getTokenTraits(tokenId);

        string memory metadata = string(
            abi.encodePacked(
                '{"name": "',
                s.isPP ? "PaperHand #" : "Holder #",
                tokenId.toString(),
                '", "description": "get rich!", "image": "',
                string(
                    abi.encodePacked(
                        currentBaseURI,
                        tokenId.toString(),
                        baseExtension
                    )
                ),
                '", "attributes": ',
                compileAttributes(tokenId),
                '"}'
            )
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    base64(bytes(metadata))
                )
            );
    }

    string internal constant TABLE =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function base64(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        // load the table into memory
        string memory table = TABLE;

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
            // set the actual output length
            mstore(result, encodedLen)

            // prepare the lookup table
            let tablePtr := add(table, 1)

            // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

            // result ptr, jump over length
            let resultPtr := add(result, 32)

            // run over the input, 3 bytes at a time
            for {

            } lt(dataPtr, endPtr) {

            } {
                dataPtr := add(dataPtr, 3)

                // read 3 bytes
                let input := mload(dataPtr)

                // write 4 characters
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(18, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(12, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(shr(6, input), 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
                mstore(
                    resultPtr,
                    shl(248, mload(add(tablePtr, and(input, 0x3F))))
                )
                resultPtr := add(resultPtr, 1)
            }

            // padding with '='
            switch mod(mload(data), 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }
        }

        return result;
    }
}

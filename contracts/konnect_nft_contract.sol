//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.11;
pragma abicoder v2; // required to accept structs as function parameters

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721URIStorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/draft-EIP712Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";

contract KCT_721_LazyNFT_V1 is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    ERC721EnumerableUpgradeable,
    ERC721URIStorageUpgradeable,
    EIP712Upgradeable
{
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    string private constant SIGNING_DOMAIN = "LazyNFT-Voucher";
    string private constant SIGNATURE_VERSION = "1";
    mapping(address => uint256) pendingWithdrawals;
    mapping(uint256 => bool) lockedTokens;
    string private baseUri;

    function initialize(
        string memory name,
        string memory symbol,
        string memory _uri
    ) public virtual initializer {
        __Ownable_init();
        __ERC721_init(name, symbol);
        __EIP712_init(SIGNING_DOMAIN, SIGNATURE_VERSION);
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
        baseUri = _uri;
    }

    struct NFTVoucher {
        uint256 tokenId;
        uint256 minPrice;
        string uri;
        bytes signature;
    }

    function redeem(
        address redeemer,
        NFTVoucher calldata voucher
    ) public payable returns (uint256) {
        address signer = _verify(voucher);
        require(
            hasRole(MINTER_ROLE, signer),
            "NFT:Signature invalid or unauthorized"
        );
        require(
            msg.value >= voucher.minPrice,
            "NFT:Insufficient funds to redeem"
        );
        _mint(signer, voucher.tokenId);
        _setTokenURI(voucher.tokenId, voucher.uri);
        _transfer(signer, redeemer, voucher.tokenId);
        pendingWithdrawals[signer] += msg.value;
        return voucher.tokenId;
    }

    function withdraw() public {
        require(
            hasRole(MINTER_ROLE, msg.sender),
            "NFT:Only authorized minters can withdraw"
        );
        address payable receiver = payable(msg.sender);
        uint256 amount = pendingWithdrawals[receiver];
        pendingWithdrawals[receiver] = 0;
        receiver.transfer(amount);
    }

    function availableToWithdraw() public view returns (uint256) {
        return pendingWithdrawals[msg.sender];
    }

    function _hash(
        NFTVoucher calldata voucher
    ) internal view returns (bytes32) {
        return
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        keccak256(
                            "NFTVoucher(uint256 tokenId,uint256 minPrice,string uri)"
                        ),
                        voucher.tokenId,
                        voucher.minPrice,
                        keccak256(bytes(voucher.uri))
                    )
                )
            );
    }

    function getChainID() external view returns (uint256) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return id;
    }

    function _verify(
        NFTVoucher calldata voucher
    ) internal view returns (address) {
        bytes32 digest = _hash(voucher);
        return ECDSAUpgradeable.recover(digest, voucher.signature);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    )
        internal
        virtual
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
    {
        require(!lockedTokens[tokenId], "NFT: locked token can't be moved");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        virtual
        override(
            AccessControlEnumerableUpgradeable,
            ERC721Upgradeable,
            ERC721EnumerableUpgradeable
        )
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _burn(
        uint256 tokenId
    )
        internal
        virtual
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
    {
        super._burn(tokenId);
    }

    function tokenURI(
        uint256 tokenId
    )
        public
        view
        virtual
        override(ERC721URIStorageUpgradeable, ERC721Upgradeable)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _mintKCT(address to, uint256 tokenId) internal {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role to mint"
        );
        super._mint(to, tokenId);
    }

    function mintKCT(
        address to,
        uint256 tokenId,
        string memory tokenURI_
    ) public {
        _mintKCT(to, tokenId);
        _setTokenURI(tokenId, tokenURI_);
    }

    function batchMintKCT(address to, uint256 offset, uint256 amount) external {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role"
        );
        require(to != address(0), "NFT: zero address");
        require(amount > 0 && amount < 0xFF, "NFT: invalid amount");
        for (uint256 i = offset; i < offset + amount; i++) {
            super._mint(to, i);
        }
    }

    function batchTransferKCT(
        address to,
        uint256 offset,
        uint256 amount
    ) external {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role"
        );
        require(to != address(0), "NFT: zero address");
        require(amount > 0 && amount < 0xFF, "NFT: invalid amount");
        for (uint256 i = offset; i < offset + amount; i++) {
            transferFrom(_msgSender(), to, i);
        }
    }

    function batchResetTokenUri(uint256 offset, uint256 amount) external {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role"
        );
        require(amount > 0 && amount < 0xFF, "NFT: invalid amount");
        for (uint256 i = offset; i < offset + amount; i++) {
            _setTokenURI(i, StringsUpgradeable.toString(i));
        }
    }

    function getTokenIds(
        address _owner
    ) public view returns (uint256[] memory) {
        uint256[] memory _tokensOfOwner = new uint256[](balanceOf(_owner));
        for (uint256 i = 0; i < balanceOf(_owner); i++) {
            _tokensOfOwner[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return (_tokensOfOwner);
    }

    function lockKCT(uint256 tokenId) public {
        require(_exists(tokenId), "NFT: operator query for nonexistent token");
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role to lock"
        );
        require(!lockedTokens[tokenId], "NFT:already locked");
        lockedTokens[tokenId] = true;
    }

    function unlockKCT(uint256 tokenId) public {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role to unlock"
        );
        require(lockedTokens[tokenId], "NFT: not locked");
        lockedTokens[tokenId] = false;
    }

    function burn(uint256 tokenId) public {
        require(
            _isApprovedOrOwner(_msgSender(), tokenId),
            "NFT: caller is not owner nor approved"
        );
        _burn(tokenId);
    }

    function resetURI(uint256 tokenId, string memory tokenURI_) public {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role to reset uri"
        );
        _setTokenURI(tokenId, tokenURI_);
    }

    function setBaseUri(string memory baseUri_) public {
        require(
            hasRole(MINTER_ROLE, _msgSender()),
            "NFT: must have minter role to reset uri"
        );
        baseUri = baseUri_;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseUri;
    }

    function version() public pure returns (string memory) {
        return "KCT: 2";
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}

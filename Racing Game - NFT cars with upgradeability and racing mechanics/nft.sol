
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title RacingNFT
 * @dev NFT Racing Game Smart Contract with upgradeable cars and racing mechanics
 * @author Your Name
 */
contract RacingNFT is ERC721, ERC721Enumerable, Ownable, ReentrancyGuard {
    uint256 private _tokenIdCounter;
    
    // Car rarity levels
    enum Rarity { COMMON, RARE, EPIC, LEGENDARY, MYTHIC }
    
    // Car statistics structure
    struct CarStats {
        uint8 speed;        // 0-100
        uint8 acceleration; // 0-100
        uint8 handling;     // 0-100
        uint8 durability;   // 0-100
        uint8 level;        // Car level (starts at 1)
        Rarity rarity;      // Car rarity
    }
    
    // Race result structure
    struct RaceResult {
        uint256 carId;
        address owner;
        uint8 position;
        uint256 reward;
        uint256 timestamp;
    }
    
    // Mapping from token ID to car stats
    mapping(uint256 => CarStats) public carStats;
    
    // Mapping from owner to racing coins balance
    mapping(address => uint256) public racingCoins;
    
    // Mapping to track car names
    mapping(uint256 => string) public carNames;
    
    // Racing history
    RaceResult[] public raceHistory;
    
    // Events
    event CarMinted(address indexed owner, uint256 indexed tokenId, Rarity rarity);
    event CarUpgraded(uint256 indexed tokenId, string stat, uint8 newValue);
    event RaceCompleted(uint256 indexed carId, uint8 position, uint256 reward);
    event CoinsEarned(address indexed player, uint256 amount);
    
    // Constants
    uint256 public constant MINT_PRICE = 0.05 ether;
    uint256 public constant UPGRADE_COST = 100; // Racing coins
    uint256 public constant RACE_ENTRY_FEE = 50; // Racing coins
    uint8 public constant MAX_STAT_VALUE = 100;
    
    constructor() ERC721("Racing NFT Cars", "RACE") Ownable(msg.sender) {
        // Give initial racing coins to contract deployer
        racingCoins[msg.sender] = 1000;
    }
    
    /**
     * @dev Mint a new racing car NFT with random stats based on rarity
     * @param to Address to mint the NFT to
     * @param carName Name for the car
     */
    function mintCar(address to, string memory carName) public payable nonReentrant {
        require(msg.value >= MINT_PRICE, "Insufficient payment");
        require(bytes(carName).length > 0, "Car name cannot be empty");
        
        uint256 tokenId = _tokenIdCounter;
        _tokenIdCounter++;
        
        // Generate random rarity (weighted distribution)
        Rarity rarity = _generateRandomRarity();
        
        // Generate base stats based on rarity
        CarStats memory newCar = _generateCarStats(rarity);
        
        // Store car data
        carStats[tokenId] = newCar;
        carNames[tokenId] = carName;
        
        // Mint the NFT
        _safeMint(to, tokenId);
        
        // Give initial racing coins to new car owner
        if (racingCoins[to] == 0) {
            racingCoins[to] = 500; // Starting bonus
        }
        
        emit CarMinted(to, tokenId, rarity);
    }
    
    /**
     * @dev Upgrade a specific stat of a car
     * @param tokenId ID of the car to upgrade
     * @param statType Type of stat to upgrade (0=speed, 1=acceleration, 2=handling, 3=durability)
     */
    function upgradeCar(uint256 tokenId, uint8 statType) public {
        require(_ownerOf(tokenId) != address(0), "Car does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this car");
        require(statType < 4, "Invalid stat type");
        require(racingCoins[msg.sender] >= UPGRADE_COST, "Insufficient racing coins");
        
        CarStats storage car = carStats[tokenId];
        
        // Check if stat can be upgraded (max 100)
        if (statType == 0) { // Speed
            require(car.speed < MAX_STAT_VALUE, "Speed already at maximum");
            car.speed = _safeAdd(car.speed, 5);
            emit CarUpgraded(tokenId, "speed", car.speed);
        } else if (statType == 1) { // Acceleration
            require(car.acceleration < MAX_STAT_VALUE, "Acceleration already at maximum");
            car.acceleration = _safeAdd(car.acceleration, 5);
            emit CarUpgraded(tokenId, "acceleration", car.acceleration);
        } else if (statType == 2) { // Handling
            require(car.handling < MAX_STAT_VALUE, "Handling already at maximum");
            car.handling = _safeAdd(car.handling, 5);
            emit CarUpgraded(tokenId, "handling", car.handling);
        } else if (statType == 3) { // Durability
            require(car.durability < MAX_STAT_VALUE, "Durability already at maximum");
            car.durability = _safeAdd(car.durability, 5);
            emit CarUpgraded(tokenId, "durability", car.durability);
        }
        
        // Deduct upgrade cost
        racingCoins[msg.sender] -= UPGRADE_COST;
        
        // Level up car every 4 upgrades
        if ((car.speed + car.acceleration + car.handling + car.durability) % 20 == 0) {
            car.level++;
        }
    }
    
    /**
     * @dev Enter a race with your car and get results
     * @param tokenId ID of the car to race
     */
    function enterRace(uint256 tokenId) public nonReentrant {
        require(_ownerOf(tokenId) != address(0), "Car does not exist");
        require(ownerOf(tokenId) == msg.sender, "Not the owner of this car");
        require(racingCoins[msg.sender] >= RACE_ENTRY_FEE, "Insufficient racing coins for entry fee");
        
        // Deduct entry fee
        racingCoins[msg.sender] -= RACE_ENTRY_FEE;
        
        // Calculate race performance based on car stats
        CarStats memory car = carStats[tokenId];
        uint256 performance = _calculateRacePerformance(car);
        
        // Add randomness to race outcome (0-50 bonus points)
        uint256 randomBonus = uint256(keccak256(abi.encodePacked(
            block.timestamp, 
            block.prevrandao, 
            msg.sender, 
            tokenId
        ))) % 51;
        
        uint256 totalScore = performance + randomBonus;
        
        // Determine race position based on total score
        uint8 position = _calculateRacePosition(totalScore);
        
        // Calculate reward based on position
        uint256 reward = _calculateRaceReward(position);
        
        // Add reward to player's racing coins
        racingCoins[msg.sender] += reward;
        
        // Record race result
        raceHistory.push(RaceResult({
            carId: tokenId,
            owner: msg.sender,
            position: position,
            reward: reward,
            timestamp: block.timestamp
        }));
        
        emit RaceCompleted(tokenId, position, reward);
        emit CoinsEarned(msg.sender, reward);
    }
    
    /**
     * @dev Get comprehensive car information
     * @param tokenId ID of the car
     * @return stats Car stats, name, and owner information
     * @return name Car name
     * @return owner Car owner address
     */
    function getCarInfo(uint256 tokenId) public view returns (
        CarStats memory stats,
        string memory name,
        address owner
    ) {
        require(_ownerOf(tokenId) != address(0), "Car does not exist");
        
        return (
            carStats[tokenId],
            carNames[tokenId],
            ownerOf(tokenId)


        );
    }
    
    /**
     * @dev Purchase racing coins with ETH
     */
    function buyRacingCoins() public payable {
        require(msg.value > 0, "Must send ETH to buy coins");
        
        // 1 ETH = 10000 racing coins
        uint256 coinsToAdd = msg.value * 10000 / 1 ether;
        racingCoins[msg.sender] += coinsToAdd;
        
        emit CoinsEarned(msg.sender, coinsToAdd);
    }
    
    // Internal helper functions
    
    function _generateRandomRarity() internal view returns (Rarity) {
        uint256 randomValue = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            block.prevrandao,
            msg.sender
        ))) % 100;
        
        if (randomValue < 50) return Rarity.COMMON;      // 50% chance
        if (randomValue < 75) return Rarity.RARE;        // 25% chance
        if (randomValue < 90) return Rarity.EPIC;        // 15% chance
        if (randomValue < 98) return Rarity.LEGENDARY;   // 8% chance
        return Rarity.MYTHIC;                            // 2% chance
    }
    
    function _generateCarStats(Rarity rarity) internal view returns (CarStats memory) {
        uint256 baseValue;
        
        // Set base stats based on rarity
        if (rarity == Rarity.COMMON) baseValue = 40;
        else if (rarity == Rarity.RARE) baseValue = 50;
        else if (rarity == Rarity.EPIC) baseValue = 65;
        else if (rarity == Rarity.LEGENDARY) baseValue = 80;
        else baseValue = 90; // MYTHIC
        
        // Add some randomness to each stat
        uint256 seed = uint256(keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender)));
        
        return CarStats({
            speed: uint8(baseValue + (seed % 15)),
            acceleration: uint8(baseValue + ((seed >> 8) % 15)),
            handling: uint8(baseValue + ((seed >> 16) % 15)),
            durability: uint8(baseValue + ((seed >> 24) % 15)),
            level: 1,
            rarity: rarity
        });
    }
    
    function _calculateRacePerformance(CarStats memory car) internal pure returns (uint256) {
        // Weighted performance calculation
        return (car.speed * 40 + car.acceleration * 30 + car.handling * 20 + car.durability * 10) / 100;
    }
    
    function _calculateRacePosition(uint256 totalScore) internal pure returns (uint8) {
        if (totalScore >= 90) return 1;      // 1st place
        if (totalScore >= 80) return 2;      // 2nd place
        if (totalScore >= 70) return 3;      // 3rd place
        if (totalScore >= 60) return 4;      // 4th place
        return 5;                            // 5th place
    }
    
    function _calculateRaceReward(uint8 position) internal pure returns (uint256) {
        if (position == 1) return 200;      // 1st place reward
        if (position == 2) return 150;      // 2nd place reward
        if (position == 3) return 100;      // 3rd place reward
        if (position == 4) return 75;       // 4th place reward
        return 50;                           // 5th place reward
    }
    
    function _safeAdd(uint8 current, uint8 increment) internal pure returns (uint8) {
        if (current + increment > MAX_STAT_VALUE) {
            return MAX_STAT_VALUE;
        }
        return current + increment;
    }
    
    // Required overrides for OpenZeppelin v5.x
    function _update(address to, uint256 tokenId, address auth) 
        internal 
        override(ERC721, ERC721Enumerable) 
        returns (address) 
    {
        return super._update(to, tokenId, auth);
    }
    
    function _increaseBalance(address account, uint128 value) 
        internal 
        override(ERC721, ERC721Enumerable) 
    {
        super._increaseBalance(account, value);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    // Owner functions
    function withdraw() public onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    function getRaceHistoryLength() public view returns (uint256) {
        return raceHistory.length;
    }
}

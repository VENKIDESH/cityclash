pragma solidity ^0.5.0;
import "./Ownable.sol";
import "./IERC20.sol";
import "./CC-modifiers.sol";
import "./ICClink.sol";

contract CityClash is Ownable , CCmodifiers{
    address public CityToken;
    uint256 public TownBasicPrice;
    uint256 public SellCommission;
    address private GameLink;

    constructor( address _GameLink) public{
            GameLink = _GameLink;
    }
    /**
    * This function is to create of ERC20 token (Gems in Game)
    * only owner Can execute function.
    * @param initialSupply total supply of token
    * @param tokenName Erc20 token Name
    * @param decimalUnits Amount of decimals for display purposes
    * @param tokenSymbol  Set the symbol for display purposes
    */
    function CreateToken(uint256 initialSupply, string memory tokenName, uint8 decimalUnits,
        string memory tokenSymbol) public onlyOwner{
        CityToken = ICClink(GameLink).createToken(initialSupply,tokenName,decimalUnits,tokenSymbol,msg.sender);
    }

    /**
    * This function handles creation of new village
    * Requires Gems to create new village.
    * Required Gems = (Number of Villages hold by user) * [(Town Basic Price) ** (Number of Villages hold by user)]
    */
    function CreateVillage() public{
        uint256 NumberOfTown = Game.getPlayerTowns().length;
        uint256 GemsRequired = NumberOfTown.mul(TownBasicPrice ** NumberOfTown);
        Game.subPlayerGems(msg.sender,GemsRequired);
        Game.addPlayerGems(address(this),GemsRequired);
        address NewTown = ICClink(GameLink).createVillage();
        Game.Villages.push(NewTown);
        Game.addPlayerVillage(NewTown);
    }
    /**
    * This function handles creation of new village
    * Requires Gems to create new village.
    * Required Gems = (Number of Villages hold by user) * [(Town Basic Price) ** (Number of Villages hold by user)]
    * @param _village address of village to destroy
    * @param _position position of village to destroy
    */
    function DestroyUserVillage(address _village,uint256 _position) public isVillageOwner(_village)
    isArrayIndex(Game.getPlayerTowns(),_position) {
        //check provided position and index corresponding to village
        isSameAddress(Game.getPlayerTowns()[_position],_village);
        ICClink(GameLink).destroyVillage(_village);
        Game.VillageOwner[_village] = address(0);
        Game.Players[msg.sender].Towns[_position] = Game.getPlayerTowns()[Game.getPlayerTowns().length - 1];
        Game.Players[msg.sender].Towns.pop();
    }
    /**
    * This function used to sell village
    * @param _village address of village to sell
    * @param _amount sell price
    * @param _position Village position on User Town list
    */
    function SellUserVillage(address _village, uint256 _amount, uint256 _position) public isVillageOwner(_village)
    isArrayIndex(Game.getPlayerTowns(),_position){
        require(_amount >= 0, "must be greater than zero");
        //check provided position and index corresponding to village
        isSameAddress(Game.getPlayerTowns()[_position],_village);
        CClibrary.MarketOrders memory Order;
        Order.SellVillage = _village;
        Order.Seller = msg.sender;
        Order.SellPrice = _amount;
        Order.TownPosition = _position;
        Game.SellOrders.push(Order);
        Game.VillageOwner[_village] = address(this);
    }
    /**
    * This function used to cancel sell village order
    * @param _position Array Index of Sell Orders list
    */
    function CancelSellOrder(uint256 _position) public isArrayLength(Game.SellOrders.length,_position){
        CClibrary.MarketOrders memory village = Game.SellOrders[_position];
        //check village belongs to contract address
        // if village not belongs to contract = already filled or cancelled order
        isSameAddress(Game.VillageOwner[village.SellVillage],address(this));
        //check Order is made by this user
        isSameAddress(village.Seller, msg.sender);
        Game.SellOrders[_position].IsFilled = true;
        Game.VillageOwner[village.SellVillage] = msg.sender;
    }
    /**
    * This function used to buy another user village
    * @param _position Array Index of Sell Orders list
    */
    function BuyUserVillage(uint256 _position) public payable isArrayLength(Game.SellOrders.length,_position)
    {
        CClibrary.MarketOrders memory village = Game.SellOrders[_position];
        isSameAddress(Game.VillageOwner[village.SellVillage],address(this));
        //check Order is not made by User
        isNotSameAddress(village.Seller,msg.sender);
        isSameValue(msg.value,village.SellPrice);
        uint256 NumberOfTown = Game.getPlayerTowns().length;
        uint256 GemsRequired = NumberOfTown.mul(TownBasicPrice ** NumberOfTown).div(2);
        Game.subPlayerGems(msg.sender,GemsRequired);
        uint256 GemtoSeller = GemsRequired.mul(SellCommission).div(100);
        uint256 GemtoContract = GemsRequired.sub(GemtoSeller);
        Game.addPlayerGems(village.Seller,GemtoSeller);
        Game.addPlayerGems(address(this),GemtoContract);
        village.Seller.transfer(msg.value);
        Game.SellOrders[_position].Buyer = msg.sender;
        Game.SellOrders[_position].IsFilled = true;
        Game.addPlayerVillage(village.SellVillage);
        Game.Players[village.Seller].Towns[village.TownPosition] = Game.Players[village.Seller].Towns[ Game.Players[village.Seller].Towns.length - 1 ];
        Game.Players[village.Seller].Towns.pop();
        //impliment gem reducton from user and give seller gem  , deduct commission from seller
    }
    /**
    * This function handles deposits of Gems to the contract.
    * If token transfer fails, transaction is reverted and remaining gas is refunded.
    * @dev Note: Remember to call Token(address).approve(this, amount) or this contract will not be able to do the transfer on your behalf.
    * @param _amount the amount of the token the user wishes to deposit
    */
    function depositGems(uint256 _amount) public {
        require(IToken(CityToken).transferFrom(msg.sender, address(this), _amount),"Token Transfer Error");
        Game.addPlayerGems(msg.sender,_amount);
    }
    /**
    *This function handles withdrawals of Gems from the contract.
    * If token transfer fails, transaction is reverted and remaining gas is refunded.
    * @param _amount uint of the amount of the token the user wishes to withdraw
    */
    function withdrawGems(uint256 _amount) public HaveGem(_amount) {
        Game.subPlayerGems(msg.sender,_amount);
        require(IToken(CityToken).transfer(msg.sender, _amount),"Token Transfer Error");
    }

    /**
    *This function handles changing of Town basic price in Gems.
    * Only Owner  can execute this function.
    * @param _value  Basic price of the town
    */
    function changeTownBasicPrice(uint256 _value) public onlyOwner{
        require(_value >= 0, "Value must be greater than zero");
        TownBasicPrice = _value;
    }
     /**
    *This function handles changing of Town sell commission in Gems.
    * Only Owner  can execute this function.
    * @param _value  sell commision in percentage
    */
    function changeSellCommission(uint256 _value) public onlyOwner{
        require(_value >= 0 && _value <= 100, "Value must be b/w 0 to 100");
        SellCommission = _value;
    }
    /**
    * function to deposite Gem on contract account balnace.
    * Only Owner  can execute this function.
    * @param _amount amount of the token
    */
    function depositGemOwner(uint256 _amount) public onlyOwner{
        require(IToken(CityToken).transferFrom(msg.sender, address(this), _amount),"Token Transfer Error");
        Game.addPlayerGems(address(this),_amount);
    }
    /**
    * function to Add building Uint in Game.
    * Only Owner  can execute this function.
    * @dev Note: Upload image to Swarm to get Hash of the file
    * @param _name name of the Building
    * @param _hash 32 byte file hash from swarm
    */
    function AddBuilding(bytes32 _name, bytes32 _hash) public onlyOwner{
        CClibrary.BuildingModel memory NewBuilding;
        NewBuilding.name = _name;
        NewBuilding.image = _hash;
        NewBuilding.state = true;
        Game.Buildings.push(NewBuilding);
    }
    /**
    * function to delete building Uint in Game.
    * Only Owner  can execute this function.
    * @param _ID index of building to be deleted from array
    */
    function DeleteBuilding(uint256 _ID) public onlyOwner isArrayLength(Game.Buildings.length,_ID){
        delete Game.Buildings[_ID];
    }
    /**
    * function to Add Troop in Game.
    * Only Owner  can execute this function.
    * @dev Note: Upload image to Swarm to get Hash of the file
    * @param _name name of the Troop
    * @param _hash 32 byte file hash from swarm
    */
    function AddTroops(bytes32 _name, bytes32 _hash) public onlyOwner{
        CClibrary.TroopsModel memory NewTroop;
        NewTroop.name = _name;
        NewTroop.image = _hash;
        NewTroop.state = true;
        Game.Troops.push(NewTroop);
    }
    /**
    * function to delete troop in Game.
    * Only Owner  can execute this function.
    * @param _ID index of troop to be deleted from array
    */
    function DeleteTroops(uint256 _ID) public onlyOwner isArrayLength(Game.Troops.length,_ID){
        delete Game.Troops[_ID];
    }
    /**
    * function to Add/Change Building Upgarde details.
    * Only Owner  can execute this function.
    * @param _ID builing id (array index)
    * @param _level Upgrade level
    * @param _RequiredBuilding Required Building ID to Upgarde
    * @param _RequiredLevel Required Building Level to Upgrade
    * @param _RequiredGold  Required Gold to upgrade
    * @param _RequiredElixr Required Elixr to upgrade
    * @param _RequiredGem Required Gem to upgrade
    * @param _GoldRate Change in gold production rate
    * @param _ElixrRate Change in elixr production rate
    * @param _GemReward amount of gem reward to user
    * @param _Time Cool off time to next Upgrade
    */
    function ChangeBuildingUpgrade(uint256 _ID, uint256 _level, uint256 _RequiredBuilding,
    uint256 _RequiredLevel, uint256 _RequiredGold, uint256 _RequiredElixr, uint256 _RequiredGem,
    uint256 _GoldRate, uint256 _ElixrRate, uint256 _GemReward, uint256 _Time) public
    isArrayLength(Game.Buildings.length,_ID) onlyOwner{
        CClibrary.UpgradeModel memory NewUpgrade;
        NewUpgrade.RequiredBuilding = _RequiredBuilding;
        NewUpgrade.RequiredLevel = _RequiredLevel;
        NewUpgrade.RequiredGold = _RequiredGold;
        NewUpgrade.RequiredElixr = _RequiredElixr;
        NewUpgrade.RequiredGem = _RequiredGem;
        NewUpgrade.GoldRate = _GoldRate;
        NewUpgrade.ElixrRate = _ElixrRate;
        NewUpgrade.GemReward = _GemReward;
        NewUpgrade.Time = _Time;
        Game.Buildings[_ID].Upgrade[_level] = NewUpgrade;
    }
    /**
    * function to Change Troop Training details.
    * Only Owner  can execute this function.
    * @param _ID troop id (array index)
    * @param _Defence Change in Defence power
    * @param _Attack Change in Attack Power
    * @param _Steal Change in Steal power
    * @param _RequiredGold  Required Gold to upgrade
    * @param _RequiredElixr Required Elixr to upgrade
    * @param _RequiredGem Required Gem to upgrade
    * @param _Time Time Required to upgrade troop
    */
    function ChangeTroopTrain(uint256 _ID, uint256 _Defence, uint256 _Attack,
    uint256 _Steal, uint256 _RequiredGold, uint256 _RequiredElixr, uint256 _RequiredGem, uint256 _Time) public
    isArrayLength(Game.Troops.length,_ID) onlyOwner{
        CClibrary.TrainModel memory NewTrain;
        NewTrain.Defence = _Defence;
        NewTrain.Attack = _Attack;
        NewTrain.Steal = _Steal;
        NewTrain.RequiredGold = _RequiredGold;
        NewTrain.RequiredElixr = _RequiredElixr;
        NewTrain.RequiredGem = _RequiredGem;
        NewTrain.Time = _Time;
        Game.Troops[_ID].Train = NewTrain;
    }
    /**
    * function to substract gem from player account.
    * Only a village can execute.
    * @param _User player address
    * @param _amount amount of gem to substract
    */
    function SubGemFromVillage(address _User, uint256 _amount) public isVillage returns(bool){
        require(_amount > 0, "Value must be greater than zero");
        Game.subPlayerGems(_User,_amount);
        Game.addPlayerGems(address(this),_amount);
        return true;
    }
     /**
    * function to add gem to player account.
    * Only a village can execute.
    * @param _User player address
    * @param _amount amount of gem to add
    */
    function AddGemFromVillage(address _User, uint256 _amount) public isVillage returns(bool){
        require(_amount > 0, "Value must be greater than zero");
        Game.subPlayerGems(address(this),_amount);
        Game.addPlayerGems(_User,_amount);
        return true;
    }
}
pragma solidity ^0.4.11;

import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

contract MonaLease is usingOraclize { 

    struct Renter {
        address addr;
        string name;
        string email;
        uint256 etherHeld;
        uint leaseStartDate;
        uint lastPaymentDate;
        bool inDefault;
        bool _assigned;
    }
    
    uint256 constant weiPerEther = 1000000000000000000;

    address contractOwner;
    string description;
    uint rentalInterval;
    uint256 rentalAmount;
    uint durationOfLease;
    
    uint lastEthPriceAsAud = 47500;
    uint rentalAmountAsWei;

    mapping (address => Renter) renters;
    address[] renterList;
    address[] rentersInDefault;
    
    event rentPaid(address renterAddress);
    event rentDefault(address renterAddress);
    
    event newOraclizeQuery(string description);
    event priceTick(uint256 price);
    

    //Note that the rental amount is in AUD cents, eg 100 AU dollars would be 10000.
    function MonaLease(string _description, uint _rentalInterval, uint _rentalAmount, uint _durationOfLease) {
        contractOwner = msg.sender;
        description = _description;
        rentalInterval = _rentalInterval;
        rentalAmount = _rentalAmount;
        durationOfLease = _durationOfLease; 
    }

    //Add a new renter
    function signLease(address _addr, string _name, string _email) {
        Renter memory _renter = Renter({
            addr: _addr,
            name: _name,
            email: _email,
            etherHeld: 0,
            leaseStartDate: now,
            lastPaymentDate: now,
            inDefault: false,
            _assigned: true
        });
        renters[_renter.addr] = _renter;
        renterList.push(_renter.addr);
    }

    function isContractOwner(address _address) returns (bool) {
        return ( _address == contractOwner);
    }

    modifier onlyContractOwner() {
        if (!isContractOwner(msg.sender)) {
            revert();
        }
        _;
    }

    // Get the account balance of a renter
    function etherHeldFor(address _renterAddress) constant returns (uint256 balance) {
        return renters[_renterAddress].etherHeld;
    }
    
    function getRenter(address _renterAddress) internal returns (Renter) {
        assert(renterExists(_renterAddress));
        return renters[_renterAddress];
    }
    
    function renterExists(address _renterAddress) returns (bool) {
        return (renters[_renterAddress]._assigned);
    }

    function deposit(address _renterAddress) payable returns (bool) {
        //If renter is registered, deposit into balance
        if (msg.value > 0 && renterExists(_renterAddress)) {
            renters[_renterAddress].etherHeld += msg.value;
        }
    }

    //Return amount due as AUD and ETH
    function getAmountDue(address _renterAddress) returns (uint256 audValue, uint256 weiValue) {
        Renter memory renter = getRenter(_renterAddress);
        uint timeElapsed = now - renter.lastPaymentDate;
        uint intervalsElapsed = timeElapsed / rentalInterval;
        audValue = intervalsElapsed * rentalAmount;
        weiValue = audToWei(audValue);
    }
    
    function takeRent(address _renterAddress) returns (bool) {
        Renter memory renter = getRenter(_renterAddress);
        uint due = getAmountDue(_renterAddress);
        if (due > renter.etherHeld) {
            renter.inDefault = true;
            return false;
        }
        else {
            contractOwner.transfer(due);
            renter.etherHeld -= due;
            renter.inDefault = false;
            renter.lastPaymentDate = now;
            return true;
        }       
    }
    
    function audToWei(audValue) returns (uint256) {
        uint256 audAsEth = 1/lastEthPriceAsAud * weiPerEther * audValue;
    }
    
    //See if any rent is due, and if so, pay it.
    function run() {
        //For each renter, getAmountDue and pay it
        for(uint i = 0; i < renterList.length; i++) {
            if (takeRent(renterList[i])) {
                rentPaid(renterList[i]);  
            }
            else {
                rentDefault(renterList[i]); 
            }

        }
    }
    
    //Schedule a price query
    function update() payable {
        uint delay;
        if (oraclize.getPrice("URL") > this.balance) {
            newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            if (lastEthPriceAsAud == 0) {
                delay = 0;
            }
            else {
                delay = 86400; //1 day
            }
            oraclize_query(delay, "URL", "json(https://api.independentreserve.com/Public/GetMarketSummary?primaryCurrencyCode=eth&secondaryCurrencyCode=aud).DayAvgPrice");
        }
    }
    
    function __callback(bytes32 myid, string result, bytes proof) {
        if (msg.sender != oraclize_cbAddress()) throw;
        lastEthPriceAsAud = parseInt(result, 2);
        priceTick(lastEthPriceAsAud);
        
        run(); //Do a rent run
        
        update(); //Now schedule a call 24 hours from now
    }

    function () {
        revert();
    }
}

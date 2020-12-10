pragma solidity ^0.5.0;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "./Valset.sol";
import "./HarmonyBridge.sol";

contract Oracle {
    using SafeMath for uint256;

    address public operator;
    uint256 public consensusThreshold; // e.g. 75 = 75%
    mapping(uint256 => address[]) public oracleClaimValidators;
    mapping(uint256 => mapping(address => bool)) public hasMadeClaim;
    HarmonyBridge public harmonyBridge;
    Valset public valset;

    event LogNewOracleClaim(
        uint256 _unlockID,
        bytes32 _message,
        address _validatorAddress,
        bytes _signature
    );

    event LogUnlockProcessed(
        uint256 _unlockID,
        uint256 _prophecyPowerCurrent,
        uint256 _prophecyPowerThreshold,
        address _submitter
    );

    modifier onlyOperator() {
        require(msg.sender == operator, "Must be the operator.");
        _;
    }

    modifier onlyValidator() {
        require(
            valset.isActiveValidator(msg.sender),
            "Must be an active validator"
        );
        _;
    }

    modifier isPending(uint256 _unlockID) {
        require(
            harmonyBridge.isUnlockClaimActive(_unlockID) == true,
            "The unlock must be pending for this operation"
        );
        _;
    }

    constructor(
        address _operator,
        address _valset,
        address _harmonyBridge,
        uint256 _consensusThreshold
    ) public {
        require(
            _consensusThreshold > 0,
            "Consensus threshold must be positive."
        );
        operator = _operator;
        harmonyBridge = HarmonyBridge(_harmonyBridge);
        valset = Valset(_valset);
        consensusThreshold = _consensusThreshold;
    }

    function newOracleClaim(
        uint256 _unlockID,
        bytes32 _message,
        bytes memory _signature
    ) public onlyValidator isPending(_unlockID) {
        address validatorAddress = msg.sender;

        require(
            validatorAddress == valset.recover(_message, _signature),
            "Invalid message signature."
        );

        require(
            !hasMadeClaim[_unlockID][validatorAddress],
            "Cannot make duplicate oracle claims from the same address."
        );

        hasMadeClaim[_unlockID][validatorAddress] = true;
        oracleClaimValidators[_unlockID].push(validatorAddress);

        emit LogNewOracleClaim(
            _unlockID,
            _message,
            validatorAddress,
            _signature
        );

        (
            // bool valid,
            ,
            uint256 unlockPowerCurrent,
            uint256 unlockPowerThreshold
        ) = getUnlockThreshold(_unlockID);

        // if (valid) {
        completeUnlock(_unlockID);

        emit LogUnlockProcessed(
            _unlockID,
            unlockPowerCurrent,
            unlockPowerThreshold,
            msg.sender
        );
        // }
    }

    function processBridgeUnlock(uint256 _unlockID)
        public
        onlyValidator
        isPending(_unlockID)
    {
        (
            // bool valid,
            ,
            uint256 unlockPowerCurrent,
            uint256 unlockPowerThreshold
        ) = getUnlockThreshold(_unlockID);

        // require(
        //     valid,
        //     "The cumulative power of signatory validators does not meet the threshold"
        // );

        // Update the BridgeClaim's status
        completeUnlock(_unlockID);

        emit LogProphecyProcessed(
            _unlockID,
            unlockPowerCurrent,
            unlockPowerThreshold,
            msg.sender
        );
    }

    function checkBridgeUnlock(uint256 _unlockID)
        public
        view
        onlyOperator
        isPending(_unlockID)
        returns (
            bool,
            uint256,
            uint256
        )
    {
        require(
            harmonyBridge.isUnlockClaimActive(_unlockID) == true,
            "Can only check active prophecies"
        );
        return getUnlockThreshold(_unlockID);
    }

    function getUnlockThreshold(uint256 _unlockID)
        internal
        view
        returns (
            bool,
            uint256,
            uint256
        )
    {
        uint256 signedPower = 0;
        uint256 totalPower = valset.totalPower();

        for (
            uint256 i = 0;
            i < oracleClaimValidators[_unlockID].length;
            i = i.add(1)
        ) {
            address signer = oracleClaimValidators[_unlockID][i];

            // Only add the power of active validators
            if (valset.isActiveValidator(signer)) {
                signedPower = signedPower.add(valset.getValidatorPower(signer));
            }
        }

        // Unlock must reach total signed power % threshold in order to pass consensus
        uint256 unlockPowerThreshold = totalPower.mul(consensusThreshold);
        // consensusThreshold is a decimal multiplied by 100, so signedPower must also be multiplied by 100
        uint256 unlockPowerCurrent = signedPower.mul(100);
        bool hasReachedThreshold = unlockPowerCurrent >=
            unlockPowerThreshold;

        return (
            hasReachedThreshold,
            unlockPowerCurrent,
            unlockPowerThreshold
        );
    }

    function completeUnlock(uint256 _unlockID) internal {
        harmonyBridge.completeUnlockClaim(_unlockID);
    }
}

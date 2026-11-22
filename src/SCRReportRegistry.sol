// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/// @title SCR Site Screening Report Registry
/// @notice Records the SHA-256 fingerprint of every Site Screening Report issued by Strategic Crypto Reserve,
///         so anyone holding a report PDF can confirm it is authentic and unaltered.
/// @dev    Only non-identifying metadata is stored: issue time, model version, location (province or state)
///         and build profile. Client names, contact details and commercial terms are never written on-chain.
contract SCRReportRegistry is AccessControl {
    bytes32 public constant ATTESTER_ROLE = keccak256("ATTESTER_ROLE");

    struct Report {
        uint64 issued;        // unix time the report was attested (0 = unknown hash)
        bool revoked;         // set if a report is withdrawn or superseded
        uint32 number;        // sequential report number, starting at 1
        bytes32 modelVersion; // e.g. "1.8.2", ASCII, right-padded
        bytes32 location;     // e.g. "British Columbia" or "Texas"
        bytes32 profile;      // e.g. "neocloud"
    }

    uint32 public count;
    mapping(bytes32 sha256Hash => Report) private _reports;

    event ReportAttested(bytes32 indexed sha256Hash, uint32 indexed number, bytes32 modelVersion, bytes32 location, bytes32 profile);
    event ReportRevoked(bytes32 indexed sha256Hash, bool revoked);

    error ZeroAddress();
    error ZeroHash();
    error AlreadyAttested();
    error UnknownReport();

    constructor(address admin, address attester) {
        if (admin == address(0) || attester == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ATTESTER_ROLE, attester);
    }

    /// @notice Record a newly issued report's SHA-256 fingerprint.
    function attest(bytes32 sha256Hash, bytes32 modelVersion, bytes32 location, bytes32 profile)
        external
        onlyRole(ATTESTER_ROLE)
        returns (uint32 number)
    {
        if (sha256Hash == bytes32(0)) revert ZeroHash();
        if (_reports[sha256Hash].issued != 0) revert AlreadyAttested();
        number = ++count;
        _reports[sha256Hash] = Report(uint64(block.timestamp), false, number, modelVersion, location, profile);
        emit ReportAttested(sha256Hash, number, modelVersion, location, profile);
    }

    /// @notice Withdraw (or reinstate) a report, e.g. if it is superseded by a corrected version.
    function setRevoked(bytes32 sha256Hash, bool revoked) external onlyRole(ATTESTER_ROLE) {
        if (_reports[sha256Hash].issued == 0) revert UnknownReport();
        _reports[sha256Hash].revoked = revoked;
        emit ReportRevoked(sha256Hash, revoked);
    }

    /// @notice What the public verify page calls. issued == 0 means the fingerprint is not on record.
    function verify(bytes32 sha256Hash)
        external
        view
        returns (uint64 issued, bool revoked, uint32 number, bytes32 modelVersion, bytes32 location, bytes32 profile)
    {
        Report memory r = _reports[sha256Hash];
        return (r.issued, r.revoked, r.number, r.modelVersion, r.location, r.profile);
    }
}

# ⏰ Time-Locked Bitcoin Trust Fund

> A secure smart contract for creating time-locked trust funds on the Stacks blockchain 🔒

## 📋 Overview

The Time-Locked Bitcoin Trust Fund is a Clarity smart contract that allows users to create trust funds that hold STX tokens for beneficiaries. The funds are locked until a specific block height is reached, ensuring that beneficiaries can only access their inheritance at the predetermined time.

## ✨ Features

- 🏦 **Trust Creation**: Create time-locked trust funds for any beneficiary
- ⏳ **Block Height Locking**: Funds locked until specific Stacks block height
- 👤 **Beneficiary Withdrawal**: Only beneficiaries can withdraw after unlock time
- 🆘 **Emergency Functions**: Grantors can withdraw in emergency situations (when enabled)
- 📈 **Fund Management**: Add additional funds or extend lock periods
- 📊 **Trust Tracking**: View trust status, remaining blocks, and statistics

## 🚀 Quick Start

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Basic understanding of Stacks blockchain and Clarity

### Installation

1. Clone this repository
2. Navigate to the project directory
3. Run `clarinet check` to verify the contract

### Deployment

```bash
clarinet deploy --testnet
```

## 📖 Usage Guide

### Creating a Trust Fund 💰

```clarity
(contract-call? .Time-Locked-Bitcoin-Trust-Fund create-trust
  'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7  ;; beneficiary
  u1000000                                        ;; amount (1 STX in microSTX)
  u1000                                          ;; unlock at block height
  "College Fund"                                 ;; trust name
)
```

### Withdrawing Funds 💳

Beneficiaries can withdraw once the unlock block height is reached:

```clarity
(contract-call? .Time-Locked-Bitcoin-Trust-Fund withdraw-trust u1)
```

### Checking Trust Status 📊

```clarity
(contract-call? .Time-Locked-Bitcoin-Trust-Fund get-trust-status u1)
```

### Managing Trust Funds 🛠️

**Extend Lock Time:**
```clarity
(contract-call? .Time-Locked-Bitcoin-Trust-Fund extend-lock-time 
  u1      ;; trust-id
  u2000   ;; new unlock block height
)
```

**Add More Funds:**
```clarity
(contract-call? .Time-Locked-Bitcoin-Trust-Fund add-funds-to-trust
  u1        ;; trust-id
  u500000   ;; additional amount
)
```

### Emergency Functions 🚨

Contract owner can enable emergency withdrawals:

```clarity
(contract-call? .Time-Locked-Bitcoin-Trust-Fund toggle-emergency-unlock)
```

Grantors can then perform emergency withdrawals:

```clarity
(contract-call? .Time-Locked-Bitcoin-Trust-Fund emergency-withdraw u1)
```

## 🔍 Contract Functions

### Public Functions

| Function | Description | Parameters |
|----------|-------------|------------|
| `create-trust` | Create a new time-locked trust | beneficiary, amount, unlock-block-height, trust-name |
| `withdraw-trust` | Withdraw funds (beneficiary only) | trust-id |
| `emergency-withdraw` | Emergency withdrawal (grantor only) | trust-id |
| `extend-lock-time` | Extend the lock period | trust-id, new-unlock-block |
| `add-funds-to-trust` | Add more funds to existing trust | trust-id, additional-amount |
| `toggle-emergency-unlock` | Enable/disable emergency mode | none |
| `transfer-ownership` | Transfer contract ownership | new-owner |

### Read-Only Functions

| Function | Description | Returns |
|----------|-------------|---------|
| `get-trust-info` | Get complete trust information | trust data or none |
| `get-user-trusts` | Get all trusts for a beneficiary | list of trust IDs |
| `get-grantor-trusts` | Get all trusts created by grantor | list of trust IDs |
| `get-contract-stats` | Get contract statistics | total trusts, value locked, emergency status |
| `is-trust-unlocked` | Check if trust is unlocked | boolean |
| `get-blocks-until-unlock` | Blocks remaining until unlock | number of blocks |
| `get-trust-status` | Complete trust status | status object |

## 🏗️ Contract Architecture

### Data Structures

- **Trusts Map**: Stores individual trust fund data
- **User Trusts Map**: Maps beneficiaries to their trust IDs
- **Grantor Trusts Map**: Maps grantors to created trust IDs

### Key Variables

- `total-trusts`: Total number of trusts created
- `total-value-locked`: Total STX locked in all trusts
- `emergency-unlock-enabled`: Emergency withdrawal status
- `contract-owner`: Contract owner principal

## 🛡️ Security Features

- ✅ **Access Control**: Only beneficiaries can withdraw their funds
- ✅ **Time Locks**: Funds cannot be accessed before unlock time
- ✅ **Emergency Controls**: Owner-controlled emergency unlock mechanism
- ✅ **Input Validation**: All parameters validated before execution
- ✅ **Reentrancy Protection**: Secure fund transfer patterns

## 🧪 Testing

Run the test suite:

```bash
clarinet test
```

## 📝 Use Cases

- 👶 **Child Trust Funds**: Lock funds until child reaches adulthood
- 🎓 **Educational Funds**: Release funds upon graduation
- 🏠 **Property Down Payments**: Save for future real estate purchases
- 💍 **Wedding Funds**: Time-locked savings for special events
- 🏥 **Emergency Funds**: Long-term financial security planning

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

## 🆘 Support

If you encounter any issues or have questions:

- Open an issue on GitHub
- Check the [Clarity documentation](https://docs.stacks.co/clarity)
- Join the [Stacks Discord](https://discord.gg/stacks)

---

Built with ❤️ using Clarity and Stacks blockchain technology

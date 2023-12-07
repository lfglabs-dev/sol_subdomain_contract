use array::ArrayTrait;
use array::SpanTrait;
use debug::PrintTrait;
use option::OptionTrait;
use zeroable::Zeroable;
use traits::Into;
use starknet::testing;
use starknet::ContractAddress;
use starknet::contract_address::ContractAddressZeroable;
use starknet::contract_address_const;
use starknet::testing::{set_contract_address, set_block_timestamp};
use super::utils;
use openzeppelin::token::erc20::{
    interface::{IERC20Camel, IERC20CamelDispatcher, IERC20CamelDispatcherTrait}
};
use identity::{
    identity::main::Identity, interface::identity::{IIdentityDispatcher, IIdentityDispatcherTrait}
};
use naming::interface::naming::{INamingDispatcher, INamingDispatcherTrait};
use naming::interface::pricing::{IPricingDispatcher, IPricingDispatcherTrait};
use naming::interface::resolver::{IResolverDispatcher, IResolverDispatcherTrait};
use naming::naming::main::Naming;
use naming::pricing::Pricing;
use sol_subdomain_distribution::interface::sol_subdomain::{
    ISolSubdomainDispatcher, ISolSubdomainDispatcherTrait
};
use sol_subdomain_distribution::main::SolSubdomain;

#[starknet::contract]
mod ERC20 {
    use openzeppelin::token::erc20::erc20::ERC20Component::InternalTrait;
    use openzeppelin::{token::erc20::{ERC20Component, dual20::DualCaseERC20Impl}};

    component!(path: ERC20Component, storage: erc20, event: ERC20Event);

    #[abi(embed_v0)]
    impl ERC20Impl = ERC20Component::ERC20Impl<ContractState>;
    #[abi(embed_v0)]
    impl ERC20CamelOnlyImpl = ERC20Component::ERC20CamelOnlyImpl<ContractState>;

    #[constructor]
    fn constructor(ref self: ContractState) {
        self.erc20.initializer('ether', 'ETH');
        let target = starknet::contract_address_const::<0x123>();
        self.erc20._mint(target, 0x100000000000000000000000000000000);
    }

    #[storage]
    struct Storage {
        #[substorage(v0)]
        erc20: ERC20Component::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        #[flat]
        ERC20Event: ERC20Component::Event,
    }
}

fn deploy() -> (
    IERC20CamelDispatcher,
    IPricingDispatcher,
    IIdentityDispatcher,
    INamingDispatcher,
    ISolSubdomainDispatcher,
    IResolverDispatcher,
) {
    let admin = 0x123;
    //erc20
    // 0, 1 = low and high of ETH supply
    let eth = utils::deploy(ERC20::TEST_CLASS_HASH, array![]);

    // pricing
    let pricing = utils::deploy(Pricing::TEST_CLASS_HASH, array![eth.into()]);

    // identity
    let identity = utils::deploy(Identity::TEST_CLASS_HASH, array![admin, 0]);

    // naming
    let naming = utils::deploy(
        Naming::TEST_CLASS_HASH, array![identity.into(), pricing.into(), 0, admin]
    );

    let sol_subdomain = utils::deploy(
        SolSubdomain::TEST_CLASS_HASH,
        array![
            admin,
            identity.into(),
            naming.into(),
            2482847743097861171204868276678300577936588859098796869235266645755324609057
        ]
    );

    (
        IERC20CamelDispatcher { contract_address: eth },
        IPricingDispatcher { contract_address: pricing },
        IIdentityDispatcher { contract_address: identity },
        INamingDispatcher { contract_address: naming },
        ISolSubdomainDispatcher { contract_address: sol_subdomain },
        IResolverDispatcher { contract_address: sol_subdomain },
    )
}

#[test]
#[available_gas(20000000000)]
fn test_claiming_subdomain() {
    let (erc20, pricing, identity, naming, sol_subdomain, resolver) = deploy();
    let caller = contract_address_const::<0x123>();
    set_contract_address(caller);

    let name = 999902; // "iris" encoded
    let sig = (
        0x5e2b889fdba808917a242634c835fde23fe82947a808811a7d0e32d0e2bb985,
        0x6a9c7e22e3f753dc4618e63ccd6c6da403a670fbf2a91263ad9c4c8a5b189fe
    );

    let max_validity: u64 = 1701167467;
    let timestamp: u64 = max_validity - 1800; // max_validity - 30 minutes
    set_block_timestamp(timestamp);

    sol_subdomain.claim(name, sig, max_validity);

    let addr = sol_subdomain.was_claimed(name);
    assert(addr == contract_address_const::<0x123>(), 'Wrong address');
}

#[test]
#[available_gas(20000000000)]
fn test_claiming_subdomain_new_owner() {
    let (erc20, pricing, identity, naming, sol_subdomain, resolver) = deploy();
    let caller = contract_address_const::<0x123>();
    set_contract_address(caller);

    let name = 999902; // "iris" encoded
    let sig1 = (
        0x5e2b889fdba808917a242634c835fde23fe82947a808811a7d0e32d0e2bb985,
        0x6a9c7e22e3f753dc4618e63ccd6c6da403a670fbf2a91263ad9c4c8a5b189fe
    );

    let max_validity: u64 = 1701167467;
    let timestamp: u64 = max_validity - 1800; // max_validity - 30 minutes
    set_block_timestamp(timestamp);

    sol_subdomain.claim(name, sig1, max_validity);
    sol_subdomain.set_resolving(name, 'starknet', caller);

    let addr = resolver.resolve(array![name].span(), 'starknet', array![].span());
    assert(addr == 0x123, 'Wrong address');

    // another user tries to claim the same subdomain because he bought it on Solana
    let sig2 = (
        0x338175390b8d981484798a2381f4aa5f7fda593268ca920b4dd9a785780fe0b,
        0x4e6b217e8a5f3d9482632d707873ea6f340d952eceaad8a105c2fe0e10a6cdc
    );
    let new_owner = contract_address_const::<0x456>();
    set_contract_address(new_owner);
    sol_subdomain.claim(name, sig2, max_validity);
    sol_subdomain.set_resolving(name, 'starknet', new_owner);

    let addr = resolver.resolve(array![name].span(), 'starknet', array![].span());
    assert(addr == 0x456, 'Wrong address');
}

#[test]
#[available_gas(20000000000)]
#[should_panic(expected: ('Signature expired', 'ENTRYPOINT_FAILED'))]
fn test_claiming_subdomain_sig_expired() {
    let (erc20, pricing, identity, naming, sol_subdomain, resolver) = deploy();
    let caller = contract_address_const::<0x123>();
    set_contract_address(caller);

    let name = 999902; // "iris" encoded
    let sig = (
        0x5e2b889fdba808917a242634c835fde23fe82947a808811a7d0e32d0e2bb985,
        0x6a9c7e22e3f753dc4618e63ccd6c6da403a670fbf2a91263ad9c4c8a5b189fe
    );

    let max_validity: u64 = 1701167467;
    let timestamp: u64 = max_validity + 1800; // max_validity + 30 minutes
    set_block_timestamp(timestamp);

    sol_subdomain.claim(name, sig, max_validity);
}

#[test]
#[available_gas(20000000000)]
#[should_panic(expected: ('Invalid signature', 'ENTRYPOINT_FAILED'))]
fn test_claiming_subdomain_sig_invalid() {
    let (erc20, pricing, identity, naming, sol_subdomain, resolver) = deploy();
    let caller = contract_address_const::<0x123>();
    set_contract_address(caller);

    let iris_encoded = 999902; // "iris" encoded
    let sig = (111, 111);
    let max_validity: u64 = 1701167467;
    let timestamp: u64 = max_validity - 1800; // max_validity + 30 minutes
    set_block_timestamp(timestamp);

    sol_subdomain.claim(iris_encoded, sig, max_validity);
}

#[test]
#[available_gas(20000000000)]
fn test_resolving() {
    let (erc20, pricing, identity, naming, sol_subdomain, resolver) = deploy();
    let caller = contract_address_const::<0x123>();
    set_contract_address(caller);

    // Buy domain sol
    let id: u128 = 1;
    let sol_domain: felt252 = 16434;
    // we mint an identity
    identity.mint(id);

    // we check how much a domain costs
    let (_, price) = pricing.compute_buy_price(3, 365);

    // we allow the naming to take our money
    erc20.approve(naming.contract_address, price);

    // we buy with a our sol contract as resolver, no sponsor, no discount and empty metadata
    naming
        .buy(id, sol_domain, 365, resolver.contract_address, ContractAddressZeroable::zero(), 0, 0);

    // We claim iris subdomain through the sol contract
    let iris_encoded = 999902;
    let sig = (
        0x5e2b889fdba808917a242634c835fde23fe82947a808811a7d0e32d0e2bb985,
        0x6a9c7e22e3f753dc4618e63ccd6c6da403a670fbf2a91263ad9c4c8a5b189fe
    );
    let max_validity: u64 = 1701167467;
    let timestamp: u64 = max_validity - 1800; // max_validity + 30 minutes
    set_block_timestamp(timestamp);

    sol_subdomain.claim(iris_encoded, sig, max_validity);
    sol_subdomain.set_resolving(iris_encoded, 'starknet', caller);

    // It should test resolving through the naming contract
    let addr = naming.resolve(array![iris_encoded, sol_domain].span(), 'starknet', array![].span());
    assert(addr == 0x123, 'Wrong address');

    // We update the resolving to a different address
    sol_subdomain.set_resolving(iris_encoded, 'starknet', contract_address_const::<0x456>());

    // Resolving the address through the naming contract should give us the new address
    let new_addr = naming
        .resolve(array![iris_encoded, sol_domain].span(), 'starknet', array![].span());
    assert(new_addr == 0x456, 'Wrong address');
}

#[test]
#[available_gas(20000000000)]
fn test_were_claimed() {
     let (erc20, pricing, identity, naming, sol_subdomain, resolver) = deploy();
    let caller = contract_address_const::<0x123>();
    set_contract_address(caller);

    let name = 999902; // "iris" encoded
    let sig = (
        0x5e2b889fdba808917a242634c835fde23fe82947a808811a7d0e32d0e2bb985,
        0x6a9c7e22e3f753dc4618e63ccd6c6da403a670fbf2a91263ad9c4c8a5b189fe
    );

    let max_validity: u64 = 1701167467;
    let timestamp: u64 = max_validity - 1800; // max_validity - 30 minutes
    set_block_timestamp(timestamp);

    sol_subdomain.claim(name, sig, max_validity);

    let mut addresses = sol_subdomain.were_claimed(array![name, name].span());
    loop {
        if addresses.len() == 0 {
            break;
        }
        let addr = addresses.pop_front().unwrap();
        assert(addr == contract_address_const::<0x123>(), 'Wrong address');
    };
}


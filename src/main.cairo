#[starknet::contract]
mod SolSubdomain {
    use starknet::ContractAddress;
    use starknet::{get_caller_address, get_block_timestamp};
    use traits::Into;
    use array::{SpanTrait, ArrayTrait};
    use starknet::class_hash::ClassHash;
    use ecdsa::check_ecdsa_signature;

    use sol_subdomain_distribution::interface::sol_subdomain::ISolSubdomain;
    use naming::interface::resolver::IResolver;
    use openzeppelin::upgrades::{UpgradeableComponent, interface::IUpgradeable};

    component!(path: UpgradeableComponent, storage: upgradeable, event: UpgradeableEvent);
    impl UpgradeableInternalImpl = UpgradeableComponent::InternalImpl<ContractState>;

    #[storage]
    struct Storage {
        identity_contract: ContractAddress,
        naming_contract: ContractAddress,
        admin: ContractAddress,
        server_pub_key: felt252,
        name_owners: LegacyMap::<felt252, ContractAddress>,
        resolving_mapping: LegacyMap::<felt252, ContractAddress>,
        #[substorage(v0)]
        upgradeable: UpgradeableComponent::Storage,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        DomainClaimed: DomainClaimed,
        DomainResolvingUpdate: DomainResolvingUpdate,
        #[flat]
        UpgradeableEvent: UpgradeableComponent::Event
    }

    #[derive(Drop, starknet::Event)]
    struct DomainClaimed {
        #[key]
        domain: Span<felt252>,
        address: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct DomainResolvingUpdate {
        #[key]
        domain: Span<felt252>,
        field: felt252,
        target_addr: ContractAddress,
    }

    #[constructor]
    fn constructor(
        ref self: ContractState,
        admin_address: ContractAddress,
        starknetid_address: ContractAddress,
        naming_address: ContractAddress,
        pub_key: felt252
    ) {
        self.identity_contract.write(starknetid_address);
        self.naming_contract.write(naming_address);
        self.admin.write(admin_address);
        self.server_pub_key.write(pub_key);
    }

    #[external(v0)]
    impl SolSubdomainImpl of ISolSubdomain<ContractState> {
        fn claim(
            ref self: ContractState, name: felt252, sig: (felt252, felt252), max_validity: u64,
        ) {
            assert(get_block_timestamp() < max_validity.try_into().unwrap(), 'Signature expired');

            let caller = get_caller_address();
            let message_hash: felt252 = hash::LegacyHash::hash(
                hash::LegacyHash::hash(hash::LegacyHash::hash('sol subdomain', max_validity), name),
                get_caller_address()
            );

            let public_key = self.server_pub_key.read();
            let (sig0, sig1) = sig;
            let is_valid = check_ecdsa_signature(message_hash, public_key, sig0, sig1);
            assert(is_valid, 'Invalid signature');

            self.name_owners.write(name, caller);

            self
                .emit(
                    Event::DomainClaimed(
                        DomainClaimed { domain: array![name].span(), address: caller, }
                    )
                )
        }

        fn was_claimed(self: @ContractState, name: felt252) -> ContractAddress {
            self.name_owners.read(name)
        }

        fn were_claimed(self: @ContractState, names: Span<felt252>) -> Array<ContractAddress> {
            let mut result: Array<ContractAddress> = array![];
            let mut names = names;
            loop {
                if names.len() == 0 {
                    break;
                }
                let name = names.pop_front().unwrap();
                result.append(self.name_owners.read(*name));
            };
            result
        }

        fn set_resolving(
            ref self: ContractState, domain: felt252, field: felt252, new_target: ContractAddress
        ) {
            let caller = get_caller_address();
            assert(self.name_owners.read(domain) == caller, 'Caller not owner of domain');
            self.resolving_mapping.write(domain, new_target);

            self
                .emit(
                    Event::DomainResolvingUpdate(
                        DomainResolvingUpdate {
                            domain: array![domain].span(), field, target_addr: new_target,
                        }
                    )
                )
        }

        // Admin functions
        fn set_admin(ref self: ContractState, new_admin: ContractAddress,) {
            assert(get_caller_address() == self.admin.read(), 'you are not admin');
            self.admin.write(new_admin);
        }

        fn set_server_pub_key(ref self: ContractState, new_pub_key: felt252,) {
            assert(get_caller_address() == self.admin.read(), 'you are not admin');
            self.server_pub_key.write(new_pub_key);
        }
    }

    #[external(v0)]
    impl ResolverImpl of IResolver<ContractState> {
        fn resolve(
            self: @ContractState, domain: Span<felt252>, field: felt252, hint: Span<felt252>
        ) -> felt252 {
            let name = *domain.at(0);
            self.resolving_mapping.read(name).into()
        }
    }

    #[external(v0)]
    impl UpgradeableImpl of IUpgradeable<ContractState> {
        fn upgrade(ref self: ContractState, new_class_hash: ClassHash) {
            assert(get_caller_address() == self.admin.read(), 'you are not admin');
            self.upgradeable._upgrade(new_class_hash);
        }
    }
}

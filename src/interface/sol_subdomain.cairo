use starknet::ContractAddress;

#[starknet::interface]
trait ISolSubdomain<TContractState> {
    fn claim(ref self: TContractState, name: felt252, sig: (felt252, felt252), max_validity: u64);
    fn set_resolving(ref self: TContractState, domain: felt252, new_target: ContractAddress);
    // Admin
    fn set_server_pub_key(ref self: TContractState, new_pub_key: felt252);
    fn set_admin(ref self: TContractState, new_admin: ContractAddress);
}

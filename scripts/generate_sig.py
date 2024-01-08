#!/usr/bin/env python3
from starkware.crypto.signature.signature import private_to_stark_key, get_random_private_key, sign
from starknet_py.hash.utils import pedersen_hash

priv_key = get_random_private_key()
print("priv_key:", hex(priv_key))

pub_key = private_to_stark_key(priv_key)
print("pub_key:", hex(pub_key))

sol_subdomain = 9145722242464647959622012987758
iris_encoded = 999902
max_validity = 1701167467
user_addr = 0x123
data = pedersen_hash(pedersen_hash(pedersen_hash(sol_subdomain, max_validity), iris_encoded), user_addr)

(x, y) = sign(data, priv_key)
print("sig:", hex(x), hex(y))
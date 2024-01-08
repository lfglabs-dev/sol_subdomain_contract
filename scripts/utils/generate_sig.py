#!/usr/bin/env python3
from starkware.crypto.signature.signature import private_to_stark_key, get_random_private_key, sign
from starknet_py.hash.utils import pedersen_hash

priv_key = get_random_private_key()
print("priv_key:", hex(priv_key))

pub_key = private_to_stark_key(priv_key)
print("pub_key:", hex(pub_key))

# hash address & session_id
data = pedersen_hash(123, 17913625103421275213921058733762211084) 

(x, y) = sign(data, priv_key)
print("sig:", hex(x), hex(y))
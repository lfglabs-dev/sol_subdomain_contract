# %% Imports
import logging
from asyncio import run

from starknet_py.cairo.felt import encode_shortstring
from utils.constants import COMPILED_CONTRACTS, ETH_TOKEN_ADDRESS
from utils.starknet import (
    deploy_v2,
    declare_v2,
    dump_declarations,
    get_starknet_account,
    dump_deployments,
)

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)


# %% Main
async def main():
    # %% Declarations
    account = await get_starknet_account()
    logger.info("ℹ️  Using account %s as deployer", hex(account.address))

    class_hash = {
        contract["contract_name"]: await declare_v2(contract["contract_name"])
        for contract in COMPILED_CONTRACTS
    }
    dump_declarations(class_hash)

    print("class_hash: ", class_hash)

    deployments = {}
    deployments["sol_subdomain_distribution_SolSubdomain"] = await deploy_v2(
        "sol_subdomain_distribution_SolSubdomain",
        0x7b38ebf26a23702f54d85c69601e3e1182de6ff633475ec45625277ff6a69a3, # identity contract v2
        0x27d2e34826dc2d2dafb012d91fafba41875d6bd2a15559c1b9181c79e06de36, # naming contract v2
        account.address, # admin address
        0x31bf4b774d069d1042fd50ab991ccbf23d6d56750c56d36370568f97b918b37 # server pub key
    )
    dump_deployments(deployments)


# %% Run
if __name__ == "__main__":
    run(main())

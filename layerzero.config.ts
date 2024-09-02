import { EndpointId } from '@layerzerolabs/lz-definitions'
import { ExecutorOptionType } from '@layerzerolabs/lz-v2-utilities'

import type { OAppEdgeConfig, OAppOmniGraphHardhat, OmniPointHardhat } from '@layerzerolabs/toolbox-hardhat'

const optimism_sepoliaContract: OmniPointHardhat = {
    eid: EndpointId.OPTSEP_V2_TESTNET,
    contractName: 'MyOApp',
}

const base_sepoliaContract: OmniPointHardhat = {
    eid: EndpointId.BASESEP_V2_TESTNET,
    contractName: 'MyOApp',
}
const DEFAULT_EDGE_CONFIG: OAppEdgeConfig = {
    enforcedOptions: [
        {
            msgType: 1,
            optionType: ExecutorOptionType.LZ_RECEIVE,
            gas: 100_000,
            value: 0,
        },
        {
            msgType: 2,
            optionType: ExecutorOptionType.COMPOSE,
            index: 0,
            gas: 100_000,
            value: 0,
        },
    ],
}

const config: OAppOmniGraphHardhat = {
    contracts: [
        {
            contract: optimism_sepoliaContract,
        },
        {
            contract: base_sepoliaContract,
        },
    ],
    connections: [
        {
            from: optimism_sepoliaContract,
            to: base_sepoliaContract,
            config: DEFAULT_EDGE_CONFIG,
        },
        {
            from: base_sepoliaContract,
            to: optimism_sepoliaContract,
            config: DEFAULT_EDGE_CONFIG,
        },
    ],
}

export default config

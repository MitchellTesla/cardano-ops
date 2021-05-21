#!/usr/bin/env bash
#
# Create the genesis file for the Shelley testnet, and the different keys that
# the nodes use.
#
# Keys and genesis files are placed in the `keys` directory.
#
# This script requires the following environment variables to be defined:
#
# - NB_BFT_NODES: number of BFT nodes
# - NB_POOL_NODES: number of staking pool nodes
# - K: the security parameter for the network
# - F: the active slot coefficient
# - MAX_SUPPLY: total lovelace supply
#
set -euo pipefail

cd "$(dirname "$0")/.."

[ -z ${NB_BFT_NODES+x} ] && (echo "Environment variable NB_BFT_NODES must be defined"; exit 1)
[ -z ${NB_POOL_NODES+x} ] && (echo "Environment variable NB_POOL_NODES must be defined"; exit 1)
[ -z ${K+x} ] && (echo "Environment variable K must be defined"; exit 1)
[ -z ${F+x} ] && (echo "Environment variable F must be defined"; exit 1)
[ -z ${MAX_SUPPLY+x} ] && (echo "Environment variable MAX_SUPPLY must be defined"; exit 1)
[ -z ${SLOT_LENGTH+x} ]&& ( echo "Environment variable SLOT_LENGTH must be defined"; exit 1)
[ -z ${NETWORK_MAGIC+x} ]&& ( echo "Environment variable NETWORK_MAGIC must be defined"; exit 1)

export NB_CORE_NODES=$(($NB_BFT_NODES + $NB_POOL_NODES))
DELAY="${DELAY:-30}"
UTXO_KEYS="${UTXO_KEYS:-3}"
DPARAM=$(awk "BEGIN{print 1.0 - 1.0 * $NB_POOL_NODES / $NB_CORE_NODES}")

echo "Generating new genesis and keys using following environments variables:

 NB_BFT_NODES=$NB_BFT_NODES (number of bft core nodes)
 NB_POOL_NODES=$NB_POOL_NODES (number of staking pool nodes)
 K=$K (Security parameter)
 F=$F (Active slots coefficient)
 MAX_SUPPLY=$MAX_SUPPLY (Max Lovelace supply)
 SLOT_LENGTH=$SLOT_LENGTH
 NETWORK_MAGIC=$NETWORK_MAGIC
 DELAY=$DELAY (delay in minutes before genesis systemStart)
 DPARAM=$DPARAM (decentralization parameter)
"

mkdir -p keys
cd keys

if [ -f "$GENESIS_PATH" ]; then
  cat $GENESIS_PATH > ./genesis.spec.json
fi

SYSTEM_START=`date -u -d "today + $DELAY minutes" +'%Y-%m-%dT%H:%M:%SZ'`

cardano-cli genesis create-staked \
            --genesis-dir . \
            --supply $((($NB_BFT_NODES + $UTXO_KEYS) * (2 * $MAX_SUPPLY) / (3 * ($NB_CORE_NODES + $UTXO_KEYS)))) \
            --supply-delegated $(($NB_POOL_NODES * (2 * $MAX_SUPPLY) / (3 * ($NB_CORE_NODES + $UTXO_KEYS)))) \
            --gen-genesis-keys $NB_BFT_NODES \
            --gen-pools $NB_POOL_NODES \
            --gen-stake-delegs $NB_POOL_NODES \
            --gen-utxo-keys $UTXO_KEYS \
            --start-time $SYSTEM_START \
            --testnet-magic $NETWORK_MAGIC

# Customize the genesis file
#
# The epoch length must satisfy:
#
#    10 * securityParam / activeSlotsCoeff <= epochLength
#
# so we set the epoch length to exactly the value of the left hand side of the
# inequality.
EPOCH_LENGTH=`perl -E "say ((10 * $K) / $F)"`
# jq will convert the big nunbers to scientific notation, and old versions of
# nix cannot handle this. Hence we need to use sed.
sed -Ei "s/^([[:blank:]]*\"updateQuorum\":)([[:blank:]]*[^,]*,)$/\1 $NB_BFT_NODES,/" genesis.json
sed -Ei "s/^([[:blank:]]*\"epochLength\":)([[:blank:]]*[^,]*,)$/\1 $EPOCH_LENGTH,/" genesis.json
sed -Ei "s/^([[:blank:]]*\"slotLength\":)([[:blank:]]*[^,]*,)$/\1 $SLOT_LENGTH,/" genesis.json
sed -Ei "s/^([[:blank:]]*\"securityParam\":)([[:blank:]]*[^,]*)$/\1 $K/" genesis.json
sed -Ei "s/^([[:blank:]]*\"activeSlotsCoeff\":)([[:blank:]]*[^,]*,)$/\1 $F,/" genesis.json
sed -Ei "s/^([[:blank:]]*\"maxLovelaceSupply\":)([[:blank:]]*[^,]*,)$/\1 $MAX_SUPPLY,/" genesis.json
sed -Ei "s/^([[:blank:]]*\"networkMagic\":)([[:blank:]]*[^,]*,)$/\1 $NETWORK_MAGIC,/" genesis.json
sed -Ei "s/^([[:blank:]]*\"decentralisationParam\":)([[:blank:]]*[^,]*)$/\1 $DPARAM/" genesis.json

cardano-cli genesis hash --genesis genesis.json > GENHASH

if [ -f $BYRON_GENESIS_PATH ]; then

  jq '.blockVersionData' \
  < $BYRON_GENESIS_PATH \
  > ./byron-genesis.spec.json

  sed -Ei "s/^([[:blank:]]*\"slotLength\":)([[:blank:]]*[^,]*,)$/\1 $SLOT_LENGTH,/" genesis.json

  rm -rf byron

  cardano-cli byron genesis genesis \
    --protocol-magic $NETWORK_MAGIC \
    --start-time `date +\%s -d "$SYSTEM_START"` \
    --k $K \
    --n-poor-addresses 0 \
    --n-delegate-addresses $NB_BFT_NODES \
    --total-balance $(($NB_BFT_NODES * (2 * $MAX_SUPPLY) / (3 * ($NB_CORE_NODES + $UTXO_KEYS)))) \
    --delegate-share $(awk "BEGIN{print $NB_BFT_NODES * 2 / (3 * ($NB_CORE_NODES + $UTXO_KEYS))}") \
    --avvm-entry-count 0 \
    --avvm-entry-balance 0 \
    --protocol-parameters-file byron-genesis.spec.json \
    --genesis-output-dir byron

  cardano-cli byron genesis print-genesis-hash --genesis-json byron/genesis.json > byron/GENHASH
fi

mkdir -p node-keys
cd node-keys
# Link VRF keys for the BFT nodes.
for i in `seq 1 $NB_BFT_NODES`; do
  ln -sf ../delegate-keys/delegate$i.vrf.skey node-vrf$i.skey
  ln -sf ../delegate-keys/delegate$i.kes.skey node-kes$i.skey
  ln -sf ../delegate-keys/opcert$i.cert node$i.opcert
done
# Link VRF keys for the staking pool nodes.
for p in `seq 1 $NB_POOL_NODES`; do
  i=$(($NB_BFT_NODES+p))
  ln -sf ../pools/vrf$p.skey node-vrf$i.skey
  ln -sf ../pools/kes$p.skey node-kes$i.skey
  ln -sf ../pools/opcert$p.cert node$i.opcert
done
# TODO fix script:
#../../scripts/renew-kes-keys.sh 0
#

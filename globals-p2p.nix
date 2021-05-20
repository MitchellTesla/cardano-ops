pkgs: with pkgs.iohkNix.cardanoLib; with pkgs.globals; {

  # This should match the name of the topology file.
  deploymentName = "p2p";

  environmentConfig = rec {
    relaysNew = "relays.${domain}";
    genesisFile = ./keys/genesis.json;
    nodeConfig =
      pkgs.lib.recursiveUpdate
      environments.shelley_qa.nodeConfig
      {
        ShelleyGenesisFile = genesisFile;
        ShelleyGenesisHash = builtins.replaceStrings ["\n"] [""] (builtins.readFile ./keys/GENHASH);
        ByronGenesisFile = ./keys/byron/genesis.json;
        ByronGenesisHash = builtins.replaceStrings ["\n"] [""] (builtins.readFile ./keys/byron/GENHASH);
        TestShelleyHardForkAtEpoch = 1;
        TestAllegraHardForkAtEpoch = 2;
        TestMaryHardForkAtEpoch = 3;
      };
    explorerConfig = mkExplorerConfig environmentName nodeConfig;
  };

  ec2 = {
    credentials = {
      accessKeyIds = {
        IOHK = "default";
        dns = "dev";
      };
    };
  };
}

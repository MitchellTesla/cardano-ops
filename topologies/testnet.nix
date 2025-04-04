pkgs: with pkgs; with lib; with topology-lib;
let

  regions = {
    a = { name = "eu-central-1";   # Europe (Frankfurt);
      minRelays = 3;
    };
    b = { name = "us-east-2";      # US East (Ohio)
      minRelays = 2;
    };
    c = { name = "ap-southeast-1"; # Asia Pacific (Singapore)
      minRelays = 1;
    };
    d = { name = "eu-west-2";      # Europe (London)
      minRelays = 2;
    };
    e = { name = "us-west-1";      # US West (N. California)
      minRelays = 2;
    };
    f = { name = "ap-northeast-1"; # Asia Pacific (Tokyo)
      minRelays = 1;
    };
  };

  stakingPoolNodes = let
    mkStakingPool = mkStakingPoolForRegions regions;
  in fullyConnectNodes [
    (mkStakingPool "a" 1 "" { nodeId = 1; })
    (mkStakingPool "b" 1 "" { nodeId = 2; })
    (mkStakingPool "c" 1 "" { nodeId = 3; })
    (mkStakingPool "d" 1 "" { nodeId = 4; })
    (mkStakingPool "e" 1 "" { nodeId = 5; })
    (mkStakingPool "f" 1 "" { nodeId = 6; })
    (mkStakingPool "a" 2 "" { nodeId = 7; })
  ];

  coreNodes = map (withAutoRestartEvery 6) stakingPoolNodes;

  relayNodes = map (withAutoRestartEvery 6) (mkRelayTopology {
    inherit regions coreNodes;
    autoscaling = false;
    maxProducersPerNode = 20;
    maxInRegionPeers = 5;
  });

in {
  inherit coreNodes relayNodes;

  services.monitoring-services.publicGrafana = true;

  "${globals.faucetHostname}" = {
    services.cardano-faucet = {
      anonymousAccess = true;
      anonymousAccessAssets = true;
      faucetLogLevel = "DEBUG";
      secondsBetweenRequestsAnonymous = 86400;
      secondsBetweenRequestsAnonymousAssets = 86400;
      secondsBetweenRequestsApiKeyAuth = 86400;
      lovelacesToGiveAnonymous = 1000000000;
      assetsToGiveAnonymous = 2;
      lovelacesToGiveApiKeyAuth = 1000000000000;
      useByronWallet = false;
      faucetFrontendUrl = "https://developers.cardano.org/en/testnets/cardano/tools/faucet/";
    };
  };
  explorer = {
    services.nginx.virtualHosts.${globals.explorerHostName}.locations."/p" = lib.mkIf (__pathExists ../static/pool-metadata) {
      root = ../static/pool-metadata;
    };
  };
}

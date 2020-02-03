import argparse
import os
import sys
import importlib.util

SOURCE_DIRECTORY = os.path.dirname(os.path.abspath(__file__)) + "/vendor/bitcoin" or os.environ['BITCOIN_SOURCE']

sys.path.append(SOURCE_DIRECTORY + "/test/functional")
from test_framework.test_framework import BitcoinTestFramework

class TestWrapper(BitcoinTestFramework):
    """Wrapper Class for BitcoinTestFramework.
    Provides the BitcoinTestFramework rpc & daemon process management
    functionality to external python projects."""

    def set_test_params(self):
        # This can be overriden in setup() parameter.
        self.num_nodes = 1

    def run_test(self):
        pass

    def setup(self,
              bitcoind=None,
              bitcoincli=None,
              setup_clean_chain=True,
              num_nodes=1,
              network_thread=None,
              rpc_timeout=60,
              supports_cli=False,
              bind_to_localhost_only=True,
              nocleanup=False,
              noshutdown=False,
              cachedir=os.path.abspath(SOURCE_DIRECTORY + "/test/cache"),
              tmpdir=None,
              loglevel='INFO',
              trace_rpc=False,
              port_seed=os.getpid(),
              coveragedir=None,
              configfile=os.path.abspath(SOURCE_DIRECTORY + "/test/config.ini"),
              pdbonfailure=False,
              usecli=False,
              perf=False,
              randomseed=None):

        self.setup_clean_chain = setup_clean_chain
        self.num_nodes = num_nodes
        self.network_thread = network_thread
        self.rpc_timeout = rpc_timeout
        self.supports_cli = supports_cli
        self.bind_to_localhost_only = bind_to_localhost_only

        self.options = argparse.Namespace
        self.options.nocleanup = nocleanup
        self.options.noshutdown = noshutdown
        self.options.cachedir = cachedir
        self.options.tmpdir = tmpdir
        self.options.loglevel = loglevel
        self.options.trace_rpc = trace_rpc
        self.options.port_seed = port_seed
        self.options.coveragedir = coveragedir
        self.options.configfile = configfile
        self.options.pdbonfailure = pdbonfailure
        self.options.usecli = usecli
        self.options.perf = perf
        self.options.randomseed = randomseed
        self.options.valgrind = False

        self.options.bitcoind = bitcoind
        self.options.bitcoincli = bitcoincli

        super().setup()

    def shutdown(self):
        super().shutdown()

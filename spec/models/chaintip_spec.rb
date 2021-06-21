# frozen_string_literal: true

require 'rails_helper'
require 'bitcoind_helper'

RSpec.describe Chaintip, type: :model do
  let(:test) { TestWrapper.new }

  def setup_python_nodes
    @use_python_nodes = true

    stub_const('BitcoinClient::Error', BitcoinClientPython::Error)
    stub_const('BitcoinClient::ConnectionError', BitcoinClientPython::ConnectionError)
    # The current commit of Bitcoin Core has wallet taproot descriptor support,
    # even when taproot is not active. We take advantage of this by creating
    # a transaction in the non-taproot wallet and then calling abandontransaction.
    #
    # TOOD: figure out how to get the "send" RPC to work ('send' is a reserved
    # keyword in Ruby and Python and this seems to confuse the wrapper)
    #
    # Once a release with Taproot support is available, it's best to use that
    # for the second node, so that this test still works when Taproot deployment
    # is burried (at which point vbparams won't work).
    test.setup(num_nodes: 3, extra_args: [['address_type=bech32m'], ['-vbparams=taproot:1:1'], ['-vbparams=taproot:1:1']])
    @node_a = create(:node_python) # Taproot enabled
    @node_a.client.set_python_node(test.nodes[0])
    @node_b = create(:node_python) # Taproot disabled
    @node_b.client.set_python_node(test.nodes[1])
    @node_c = create(:node_python) # Taproot disabled (doesn't really matter)
    @node_c.client.set_python_node(test.nodes[2])

    # Disconnect Node C so we can give it a an independent chain
    @node_c.client.setnetworkactive(false)
    test.disconnect_nodes(0, 2)
    test.disconnect_nodes(1, 2)

    @node_a.client.createwallet
    @node_b.client.createwallet(blank: true)
    @node_b.client.importdescriptors([
                                       {
                                         desc: 'tr(tprv8ZgxMBicQKsPeNLUGrbv3b7qhUk1LQJZAGMuk9gVuKh9sd4BWGp1eMsehUni6qGb8bjkdwBxCbgNGdh2bYGACK5C5dRTaif9KBKGVnSezxV/0/*)#c8796lse', active: true, internal: false, timestamp: 'now', range: 10
                                       },
                                       {
                                         desc: 'tr(tprv8ZgxMBicQKsPeNLUGrbv3b7qhUk1LQJZAGMuk9gVuKh9sd4BWGp1eMsehUni6qGb8bjkdwBxCbgNGdh2bYGACK5C5dRTaif9KBKGVnSezxV/1/*)#fnmy82qp', active: true, internal: true, timestamp: 'now', range: 10
                                       }
                                     ])
    @addr_1 = @node_b.client.getnewaddress
    @addr_2 = @node_b.client.getnewaddress
    @r_addr = @node_a.client.getnewaddress

    @node_a.client.generatetoaddress(2, @r_addr)
    test.sync_blocks([@node_a.client, @node_b.client])

    @node_a.poll!
    @node_a.reload
    assert_equal(@node_a.block.height, 2)
    expect(@node_a.block.parent).not_to be_nil
    assert_equal(@node_a.block.parent.height, 1)
    assert_equal(Chaintip.count, 0)

    @node_b.poll!
    @node_b.reload
    assert_equal(@node_b.block.height, 2)
    assert_equal(@node_b.block.parent.height, 1)
    assert_equal(Chaintip.count, 0)

    @node_c.client.createwallet
    @addr_3 = @node_c.client.getnewaddress
    @node_c.client.generatetoaddress(3, @addr_3) # longer chain than A and B, so it won't validate those blocks
    # Node C intentionally remains disconnected from A and B
  end

  after do
    test.shutdown if @use_python_nodes
  end

  describe 'process_active!' do
    before do
      setup_python_nodes
    end

    it 'creates fresh chaintip for a new node' do
      tip = described_class.process_active!(@node_a, @node_a.block)
      expect(tip.id).not_to be_nil
    end

    it 'does not update existing chaintip entry if the block unchanged' do
      tip_before = described_class.process_active!(@node_a, @node_a.block)
      @node_a.poll!
      tip_after = described_class.process_active!(@node_a, @node_a.block)
      expect(tip_before).to eq(tip_after)
    end

    it 'updates existing chaintip entry if the block changed' do
      tip_before = described_class.process_active!(@node_a, @node_a.block)
      @node_a.client.generate(1)
      @node_a.poll!
      tip_after = described_class.process_active!(@node_a, @node_a.block)
      expect(tip_before.id).to eq(tip_after.id)
      expect(tip_after.block).to eq(@node_a.block)
    end

    it 'creates fresh chaintip for the different node' do
      tip_a = described_class.process_active!(@node_a, @node_a.block)
      tip_b = described_class.process_active!(@node_b, @node_b.block)
      expect(tip_a).not_to eq(tip_b)
    end
  end

  describe 'nodes_for_identical_chaintips / process_active!' do
    let(:block_1) { create(:block) }
    let(:block_2) { create(:block, parent: block_1) }
    let(:node_a) { create(:node, block: block_1) }
    let(:node_b) { create(:node) }
    let(:node_c) { create(:node) }
    let(:chaintip_1) { create(:chaintip, block: block_1, node: node_a) }
    let(:chaintip_2) { create(:chaintip, block: block_1, node: node_b) }

    it 'shows all nodes at height of active chaintip' do
      setup_python_nodes
      @tip_a = described_class.process_active!(@node_a, @node_a.block)
      @tip_b = described_class.process_active!(@node_b, @node_b.block)
      assert_equal 2, @tip_a.nodes_for_identical_chaintips.count
      assert_equal [@node_a, @node_b], @tip_a.nodes_for_identical_chaintips
    end

    it 'onlies support the active chaintip' do
      chaintip_1.update status: 'invalid'
      assert_nil chaintip_1.nodes_for_identical_chaintips
      assert_nil chaintip_1.nodes_for_identical_chaintips
    end
  end

  describe 'process_valid_headers!' do
    before do
      setup_python_nodes
    end

    it 'does nothing if we already know the block' do
      block = Block.create(coin: :btc, block_hash: '1234', height: 5)
      expect(Block).not_to receive(:create_headers_only)
      described_class.process_valid_headers!(@node_a, { 'hash' => '1234', 'height' => 5 }, block)
    end

    it 'creates headers_only block entry' do
      expect(Block).to receive(:create_headers_only)
      described_class.process_valid_headers!(@node_a, { 'hash' => '1234', 'height' => 5 }, nil)
    end
  end

  describe 'match_parent!' do
    let(:node_a) { create(:node) }
    let(:node_b) { create(:node) }
    let(:block_1) { create(:block) }
    let(:block_2) { create(:block, parent: block_1) }
    let(:block_3) { create(:block, parent: block_2) }
    let(:chaintip_1) { create(:chaintip, block: block_1, node: node_a) }
    let(:chaintip_2) { create(:chaintip, block: block_1, node: node_b) }

    it 'does nothing if all nodes are the same height' do
      chaintip_2.match_parent!(node_b)
      assert_nil chaintip_2.parent_chaintip
    end

    describe 'when another chaintip is longer' do
      before do
        chaintip_1.update block: block_2
      end

      it 'marks longer chain as parent' do
        chaintip_2.match_parent!(node_b)
        assert_equal(chaintip_2.parent_chaintip, chaintip_1)
      end

      it 'marks even longer chain as parent' do
        chaintip_1.update block: block_3
        chaintip_2.match_parent!(node_b)
        assert_equal(chaintip_2.parent_chaintip, chaintip_1)
      end

      it 'does not mark invalid chain as parent' do
        # Node B considers block b invalid:
        chaintip_3 = create(:chaintip, block: block_2, node: node_b, status: 'invalid') # rubocop:disable Lint/UselessAssignment

        chaintip_2.match_parent!(node_b)
        assert_nil(chaintip_2.parent_chaintip)
      end

      it 'does not mark invalid chain as parent, based on block marked invalid' do
        # Node B considers block b invalid:
        block_2.update marked_invalid_by: block_2.marked_invalid_by | [node_b.id]

        chaintip_2.match_parent!(node_b)
        assert_nil(chaintip_2.parent_chaintip)
      end
    end
  end

  describe 'check_parent!' do
    let(:node_a) { create(:node) }
    let(:node_b) { create(:node) }
    let(:block_1) { create(:block) }
    let(:block_2) { create(:block, parent: block_1) }
    let(:block_3) { create(:block, parent: block_2) }
    let(:chaintip_1) { create(:chaintip, block: block_1, node: node_a) }
    let(:chaintip_2) { create(:chaintip, block: block_1, node: node_b) }

    describe 'when another chaintip is longer' do
      before do
        chaintip_1.update block: block_2
      end

      it 'unmarks parent if it later considers it invalid' do
        chaintip_2.update parent_chaintip: chaintip_1 # For example via match_children!

        chaintip_3 = create(:chaintip, block: block_2, node: node_b, status: 'invalid') # rubocop:disable Lint/UselessAssignment
        chaintip_2.check_parent!(node_b)
        assert_nil(chaintip_2.parent_chaintip)
      end
    end
  end

  describe 'match_children!' do
    let(:node_a) { create(:node) }
    let(:node_b) { create(:node) }
    let(:block_1) { create(:block) }
    let(:block_2) { create(:block, parent: block_1) }
    let(:chaintip_1) { create(:chaintip, block: block_1, node: node_a) }
    let(:chaintip_2) { create(:chaintip, block: block_1, node: node_b) }

    it 'does nothing if all nodes are the same height' do
      chaintip_1.match_children!(node_b)
      assert_nil chaintip_1.parent_chaintip
    end

    describe 'when another chaintip is shorter' do
      before do
        chaintip_1.update block: block_2
        chaintip_2 # lazy load
      end

      it 'marks itself as the parent' do
        chaintip_1.match_children!(node_b)
        chaintip_2.reload
        assert_equal(chaintip_2.parent_chaintip, chaintip_1)
      end

      it 'does not mark itself as parent if the other node considers it invalid' do
        # Node B considers block b invalid:
        chaintip_3 = create(:chaintip, block: block_2, node: node_b, status: 'invalid') # rubocop:disable Lint/UselessAssignment
        chaintip_1.match_children!(node_b)
        chaintip_2.reload
        assert_nil(chaintip_2.parent_chaintip)
      end
    end
  end

  describe 'check!' do
    before do
      setup_python_nodes
    end

    describe 'one node in IBD' do
      it 'does nothing' do
        @node_a.update ibd: true
        described_class.check!(:btc, [@node_a])
        expect(@node_a.chaintips.count).to eq(0)
      end
    end

    describe 'only an active chaintip' do
      it 'adds a chaintip entry' do
        expect(@node_a.chaintips.count).to eq(0)
        described_class.check!(:btc, [@node_a])
        expect(@node_a.chaintips.count).to eq(1)
        expect(@node_a.chaintips.first.block.height).to eq(2)
      end
    end

    describe 'one active and one valid-fork chaintip' do
      before do
        test.disconnect_nodes(0, 1)
        assert_equal(0, @node_a.client.getpeerinfo.count)

        @node_a.client.generate(2) # this will be a valid-fork after reorg
        @node_b.client.generate(3) # reorg to this upon reconnect
        @node_a.poll!
        @node_b.poll!
        test.connect_nodes(0, 1)
        test.sync_blocks([@node_a.client, @node_b.client])
      end

      it 'adds chaintip entries' do
        described_class.check!(:btc, [@node_a])
        expect(@node_a.chaintips.count).to eq(2)
        expect(@node_a.chaintips.last.status).to eq('valid-fork')
      end

      it 'adds the valid fork blocks up to the common ancenstor' do
        described_class.check!(:btc, [@node_a])
        @node_a.reload
        split_block = Block.find_by(height: 2)
        fork_tip = @node_a.block
        expect(fork_tip.height).to eq(4)
        expect(fork_tip).not_to be_nil
        expect(fork_tip.parent).not_to be_nil
        expect(fork_tip.parent.height).to eq(3)
        expect(fork_tip.parent.parent).to eq(split_block)
      end

      it 'ignores forks more than 1000 blocks ago' do
        # 10 on regtest
        test.disconnect_nodes(0, 1)
        assert_equal(0, @node_a.client.getpeerinfo.count)

        @node_a.client.generate(11) # this will be a valid-fork after reorg
        @node_b.client.generate(12) # reorg to this upon reconnect
        @node_a.poll!
        @node_b.poll!
        test.connect_nodes(0, 1)

        described_class.check!(:btc, [@node_a])
        expect(@node_a.chaintips.count).to eq(2)
      end
    end

    describe 'node_a ahead of node_b' do
      before do
        @node_a.client.generate(2)
        @node_a.poll!
        @node_b.poll!
        # Disconnect nodes and produce one more block for A
        test.disconnect_nodes(0, 1)
        assert_equal(0, @node_a.client.getpeerinfo.count)
        @node_a.client.generate(1)
        @node_a.poll!
        described_class.check!(:btc, [@node_a, @node_b])
      end

      it 'matches parent block' do
        tip_a = @node_a.chaintips.where(status: 'active').first
        tip_b = @node_b.chaintips.where(status: 'active').first
        expect(tip_a).not_to be(tip_b)
        expect(tip_b.parent_chaintip).to eq(tip_a)
      end
    end

    describe 'invalid chaintip' do
      before do
        # Reach coinbase maturity
        @node_a.client.generatetoaddress(99, @r_addr)

        # Fund a taproot address and mine it
        @node_a.client.sendtoaddress(@addr_1, 1)
        @node_a.client.generate(1)
        test.sync_blocks([@node_a.client, @node_b.client])

        # Spend from taproot address (this node has taproot disabled, so it won't broadcast)
        tx_id = @node_b.client.sendtoaddress(@r_addr, 0.1)
        tx_hex = @node_b.client.gettransaction(tx_id)['hex']
        @node_b.client.abandontransaction(tx_id)

        txs = @node_b.client.listtransactions
        assert_equal(txs[1]['txid'], tx_id)
        assert_equal(txs[1]['abandoned'], true)

        mempool_tap = @node_a.client.testmempoolaccept([tx_hex])[0]
        mempool_no_tap = @node_b.client.testmempoolaccept([tx_hex])[0]
        expect(mempool_tap['allowed']).to eq(true)
        expect(mempool_no_tap['allowed']).to eq(false)
        expect(mempool_no_tap['reject-reason']).to eq('bad-txns-nonstandard-inputs')

        # Cripple transaction so that it's invalid under taproot rules
        tx_hex[-20] = if tx_hex[-20] == '0'
                        'f'
                      else
                        '0'
                      end

        mempool_broken_tap = @node_a.client.testmempoolaccept([tx_hex])[0]
        mempool_broken_no_tap = @node_b.client.testmempoolaccept([tx_hex])[0]

        expect(mempool_broken_no_tap['allowed']).to eq(false)
        expect(mempool_broken_no_tap['reject-reason']).to eq('bad-txns-nonstandard-inputs')

        expect(mempool_broken_tap['allowed']).to eq(false)
        expect(mempool_broken_tap['reject-reason']).to eq('non-mandatory-script-verify-flag (Invalid Schnorr signature)')

        # @node_a.client.sendrawtransaction(tx_hex)
        block_hex = test.createtaprootblock([tx_hex])
        @node_b.client.submitblock(block_hex)
        sleep(1)

        @disputed_block_hash = @node_b.client.getbestblockhash
      end

      describe 'not in our db' do
        before do
          # Don't poll node B, so our DB won't contain the disputed block
          @node_a.poll!
        end

        it 'stores the block' do
          described_class.check!(:btc, [@node_a])
          block = Block.find_by(block_hash: @disputed_block_hash)
          expect(block).not_to be_nil
        end

        it 'marks the block as invalid' do
          described_class.check!(:btc, [@node_a])
          block = Block.find_by(block_hash: @disputed_block_hash)
          expect(block).not_to be_nil
          expect(block.marked_invalid_by).to include(@node_a.id)
        end

        it 'stores invalid tip' do
          described_class.check!(:btc, [@node_a])
          expect(@node_a.chaintips.where(status: 'invalid').count).to eq(1)
        end
      end

      describe 'in our db' do
        before do
          @node_a.poll!
          @node_b.poll!
        end

        it 'marks the block as invalid' do
          described_class.check!(:btc, [@node_a])
          block = Block.find_by(block_hash: @disputed_block_hash)
          expect(block).not_to be_nil
          expect(block.marked_invalid_by).to include(@node_a.id)
        end

        it 'stores invalid tip' do
          described_class.check!(:btc, [@node_a])
          expect(@node_a.chaintips.where(status: 'invalid').count).to eq(1)
        end

        it 'is nil if the node is unreachable' do
          @node_a.client.mock_connection_error(true)
          @node_a.poll!
          described_class.check!(:btc, [@node_a])
          expect(@node_a.chaintips.count).to eq(0)
        end
      end
    end
  end

  describe 'self.validate_forks!' do
    before do
      setup_python_nodes

      # Feed blocks from node B to node C so their status changes from 'headers-only'
      # to 'valid-headers'
      assert_equal(@node_c.client.submitblock(@node_b.client.getblock(@node_b.client.getblockhash(1), 0)), 'inconclusive')
      assert_equal(@node_c.client.submitblock(@node_b.client.getblock(@node_b.client.getblockhash(2), 0)), 'inconclusive')

      # Now connect them (node_b will reorg)
      @node_c.client.setnetworkactive(true)
      test.connect_nodes(1, 2)
      test.sync_blocks([@node_b.client, @node_c.client])
    end

    it "calls block.validate_fork! on 'valid-headers' tips" do
      # pp @node_c.client.getchaintips()
      block = Block.new
      expect(Block).to receive(:find_by).and_return block
      expect(block).to receive(:validate_fork!)
      described_class.validate_forks!(@node_c, 100)
    end

    it 'ignores old tips' do
      # pp @node_c.client.getchaintips()
      expect(Block).not_to receive(:find_by)
      @node_c.client.generatetoaddress(1, @addr_3)
      described_class.validate_forks!(@node_c, 1)
    end
  end
end

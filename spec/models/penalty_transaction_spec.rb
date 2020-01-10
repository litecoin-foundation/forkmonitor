require 'rails_helper'

RSpec.describe PenaltyTransaction, type: :model do
  before do
    @node = build(:node, version: 170001)
    @node.client.mock_set_height(560176)
    @node.poll!
    @node.reload

    expect(Block.maximum(:height)).to eq(560176)
    allow(Node).to receive(:bitcoin_core_by_version).and_return [@node]

    allow(PenaltyTransaction).to receive(:check!).and_return nil

    # throw the first time for lacking a previously checked block
    expect{ LightningTransaction.check!({coin: :btc, max: 1}) }.to raise_error("Unable to perform lightning checks due to missing intermediate block")
    @node.client.mock_set_height(560177)
    @node.poll!
    @node.reload
  end

  describe "check!" do
    before do
      allow(PenaltyTransaction).to receive(:check!).and_call_original
      allow_any_instance_of(PenaltyTransaction).to receive(:get_opening_tx_id!).and_return nil
      @block = Block.find_by(height: 560177)
      raw_block = @node.client.getblock(@block.block_hash, 0)
      @parsed_block = Bitcoin::Protocol::Block.new([raw_block].pack('H*'))
      # Example from https://blog.bitmex.com/lightning-network-justice/
      @raw_tx = "02000000000101031e7c67d770fb2a24eafd655f6013281e6ae34596649c07e6b4ee2d4a8dc25c000000000000000000014ef5050000000000160014befc2bfa5ad1be99da557f180ae91bd7b666d11403483045022100bd5c4c29e6b686aae5b6d0751e90208592ea96d26bc81d78b0d3871a94a21fa8022074dc2f971e438ccece8699c8fd15704c41df219ab37b63264f2147d15c3481d80101014d6321024cf55e52ec8af7866617dc4e7ff8433758e98799906d80e066c6f32033f685f967029000b275210214827893e2dcbe4ad6c20bd743288edad21100404eb7f52ccd6062fd0e7808f268ac00000000"
      @penalty_tx = Bitcoin::Protocol::Tx.new([@raw_tx].pack('H*'))
      expect(@penalty_tx.hash).to eq("c5597bbe1f56ea72ae4b6e2835d69c1767c3ce1317da5352aa14dad8ed22df34")
      @parsed_block.tx.append(@penalty_tx)
    end

    it "should find penalty transactions" do
      PenaltyTransaction.check!(@block, @parsed_block)
      expect(LightningTransaction.count).to eq(1)
      expect(LightningTransaction.first.tx_id).to eq(@penalty_tx.hash)
      expect(LightningTransaction.first.raw_tx).to eq(@raw_tx)
    end

    it "should set the amount based on the output" do
      PenaltyTransaction.check!(@block, @parsed_block)
      expect(LightningTransaction.first.amount).to eq(0.00390478)
    end

    it "should find opening transaction" do
      skip()
    end

  end

end
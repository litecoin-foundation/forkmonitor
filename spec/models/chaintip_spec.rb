require 'rails_helper'

RSpec.describe Chaintip, type: :model do
  describe "process_active!" do
    let(:nodeA) { create(:node) }
    let(:nodeB) { create(:node) }
    let(:block1) { create(:block) }
    let(:block2) { create(:block, parent: block1) }
    let(:block3) { create(:block, parent: block2) }
    let(:chaintip1) { create(:chaintip, block: block2, node: nodeA) }

    it "should reuse chaintip for the same block" do
      chaintip1 # ensure it's instantiated before the next line
      tip = Chaintip.process_active!(nodeB, block2)
      expect(tip).to eq(chaintip1)
    end

    it "should match parent block" do
      chaintip1
      tip = Chaintip.process_active!(nodeB, block1)
      expect(tip).not_to be(chaintip1)
      expect(tip.parent_chaintip).to eq(chaintip1)
    end

    it "should match child block" do
      chaintip1
      # Feed node B a chaintip that's more recent than the chaintip for node A
      tip = Chaintip.process_active!(nodeB, block3)
      expect(tip).not_to be(chaintip1)
      chaintip1.reload
      expect(chaintip1.parent_chaintip).to eq(tip)
    end
  end

  describe "nodes / process_active!" do
    let(:nodeA) { create(:node) }
    let(:nodeB) { create(:node) }
    let(:block1) { create(:block) }
    let(:block2) { create(:block, parent: block1) }
    let(:chaintip1) { create(:chaintip, block: block1, node: nodeA) }

    it "should only support the active chaintip" do
      chaintip1.update status: "invalid"
      assert_nil chaintip1.nodes
    end

    it "should the original node for this active chaintip" do
      assert_equal chaintip1.nodes, [nodeA]
    end

    it "should show all nodes at height of active chaintip" do
      Chaintip.process_active!(nodeB, block1)
      assert_equal 2, chaintip1.nodes.count
      assert_equal [nodeB, nodeA], chaintip1.nodes
    end

    it "should include parent blocks in chaintip" do
      chaintip1.update block: block2
      Chaintip.process_active!(nodeB, block1)
      assert_equal 2, chaintip1.nodes.count
      assert_equal [nodeA, nodeB], chaintip1.nodes
    end

  end

  describe "match_parent!" do
    let(:nodeA) { create(:node) }
    let(:nodeB) { create(:node) }
    let(:block1) { create(:block) }
    let(:block2) { create(:block, parent: block1) }
    let(:block3) { create(:block, parent: block2) }
    let(:chaintip1) { create(:chaintip, block: block1, node: nodeA) }
    let(:chaintip2) { create(:chaintip, block: block1, node: nodeB) }

    it "should do nothing if all nodes are the same height" do
      chaintip2.match_parent!(nodeB)
      assert_nil chaintip2.parent_chaintip
    end

    describe "when another chaintip is longer" do
      before do
        chaintip1.update block: block2
      end

      it "should mark longer chain as parent" do
        chaintip2.match_parent!(nodeB)
        assert_equal(chaintip2.parent_chaintip, chaintip1)
      end


      it "should mark even longer chain as parent" do
        chaintip1.update block: block3
        chaintip2.match_parent!(nodeB)
        assert_equal(chaintip2.parent_chaintip, chaintip1)
      end

      it "should not mark invalid chain as parent" do
        # Node B considers block b invalid:
        chaintip3 = create(:chaintip, block: block2, node: nodeB, status: "invalid")

        chaintip2.match_parent!(nodeB)
        assert_nil(chaintip2.parent_chaintip)
      end

      it "should unmark parent if it later considers it invalid" do
        chaintip2.update parent_chaintip: chaintip1 # For example via match_children!

        chaintip3 = create(:chaintip, block: block2, node: nodeB, status: "invalid")
        chaintip2.match_parent!(nodeB)
        assert_nil(chaintip2.parent_chaintip)
      end

    end

  end

  describe "match_children!" do
    let(:nodeA) { create(:node) }
    let(:nodeB) { create(:node) }
    let(:block1) { create(:block) }
    let(:block2) { create(:block, parent: block1) }
    let(:chaintip1) { create(:chaintip, block: block1, node: nodeA) }
    let(:chaintip2) { create(:chaintip, block: block1, node: nodeB) }

    it "should do nothing if all nodes are the same height" do
      chaintip1.match_children!(nodeB)
      assert_nil chaintip1.parent_chaintip
    end

    describe "when another chaintip is shorter" do
      before do
        chaintip1.update block: block2
        chaintip2 # lazy load
      end

      it "should mark itself as the parent" do
        chaintip1.match_children!(nodeB)
        chaintip2.reload
        assert_equal(chaintip2.parent_chaintip, chaintip1)
      end

      it "should not mark itself as parent if the other node considers it invalid" do
        # Node B considers block b invalid:
        chaintip3 = create(:chaintip, block: block2, node: nodeB, status: "invalid")
        chaintip1.match_children!(nodeB)
        chaintip2.reload
        assert_nil(chaintip2.parent_chaintip)
      end
    end
  end
end

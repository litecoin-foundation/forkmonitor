MINIMUM_BLOCK_HEIGHT = 560176 # Tests need to be adjusted if this number is increased

class Block < ApplicationRecord
  has_many :children, class_name: 'Block', foreign_key: 'parent_id'
  belongs_to :parent, class_name: 'Block', foreign_key: 'parent_id', optional: true
  has_many :invalid_blocks
  belongs_to :first_seen_by, class_name: 'Node', foreign_key: 'first_seen_by_id', optional: true
  enum coin: [:btc, :bch, :bsv]

  def as_json(options = nil)
    super({ only: [:height, :timestamp] }.merge(options || {})).merge({
      id: id,
      hash: block_hash,
      timestamp: timestamp,
      work: log2_pow,
      pool: pool,
      first_seen_by: first_seen_by ? {
        id: first_seen_by.id,
        name: first_seen_by.name,
        version: first_seen_by.version
      } : nil})
  end

  def log2_pow
    return nil if work.nil?
    Math.log2(work.to_i(16))
  end

  def version_bits
    # First three bits of field have no meaning in BIP9. nVersion is a little-endian
    # signed integer that must be greater than 2, which is 0x0010 in binary and 0x02 in hex.
    # By setting the least significant byte to >= 0x02 this requirement is met
    # regardless of the next 3 bytes.
    # This is why nVersion changed from 4 (0x00000004) to 536870912 (0x20000000) for most blocks.
    # In fact, nVersion 4 (0x00000004) would now indicate signalling for a soft fork on bit 26.
    #        mask: 0xe0000000 (bit 0-28)
    # BIP320 mask: 0xe0001fff (loses bit 13-28)
    ("%.32b" % (self.version & ~0xe0000000)).split("").drop(3).reverse().collect{|s|s.to_i}
  end

  def find_ancestors!(node, until_height = nil)
    # Prevent new instances from going too far back:
    block_id = self.id
    loop do
      block = Block.find(block_id)
      return if until_height ? block.height == until_height : block.height <= MINIMUM_BLOCK_HEIGHT
      parent = block.parent
      if parent.nil?
        if node.client_type.to_sym == :libbitcoin
          block_info = node.client.getblockheader(block.block_hash)
        else
          block_info = node.client.getblock(block.block_hash)
        end
        parent = Block.find_by(block_hash: block_info["previousblockhash"])
        block.update parent: parent
      end
      if parent.present?
        return if until_height.nil?
      else
        # Fetch parent block:
        break if !self.id
        puts "Fetch intermediate block at height #{ block.height - 1 }" unless Rails.env.test?
        if node.client_type.to_sym == :libbitcoin
          block_info = node.client.getblockheader(block_info["previousblockhash"])
        else
          block_info = node.client.getblock(block_info["previousblockhash"])
        end

        # Set pool:
        pool = node.get_pool_for_block!(block_info["hash"], block_info)

        parent = Block.create(
          coin: self.coin,
          block_hash: block_info["hash"],
          height: block_info["height"],
          mediantime: block_info["mediantime"],
          timestamp: block_info["time"],
          work: block_info["chainwork"],
          version: block_info["version"],
          first_seen_by: node,
          pool: pool
        )
        block.update parent: parent
      end
      block_id = parent.id
    end
  end

  def self.pool_from_coinbase_tx(tx)
    return nil if tx["vin"].nil? || tx["vin"].empty?
    coinbase = nil
    tx["vin"].each do |vin|
      coinbase = vin["coinbase"]
      break if coinbase.present?
    end
    throw "not a coinbase" if coinbase.nil?
    message = [coinbase].pack('H*')

    pools_ascii = {
      "AntPool" => "Antpool",
      "BTC.COM" => "BTC.com",
      "/slush/" => "SlushPool",
      "/ViaBTC/" => "ViaBTC",
      "/BTC.TOP/" => "BTC.TOP",
      "/Bitfury/" => "BitFury",
      "/BitClub Network/" => "BitClub",
      "BitMinter" => "BitMinter",
      "/pool.bitcoin.com/" => "bitcoin.com",
    }

    pools_utf8 = {
        "🐟" => "F2Pool"
    }

    pools_ascii.each do |match, name|
      return name if message.include?(match)
    end
    message_utf8 = message.force_encoding('UTF-8')
    pools_utf8.each do |match, name|
      return name if message_utf8.include?(match)
    end
    return nil
  end

  def self.check_inflation!
    # Use the latest node for this check
    node = Node.bitcoin_core_by_version.first
    throw "Node in Initial Blockchain Download" if node.ibd

    puts "Get the total UTXO balance at the tip..." unless Rails.env.test?
    txoutsetinfo = node.client.gettxoutsetinfo

    # Make sure we have all blocks up to the tip
    block = Block.find_by(block_hash: txoutsetinfo["bestblock"])
    if block.nil?
      puts "Fetch recent blocks..." unless Rails.env.test?
      node.poll!
      # Try again. The tip may move already moved on because gettxoutsetinfo is slow.
      block = Block.find_by(block_hash: txoutsetinfo["bestblock"])

      if block.nil?
        throw "Latest block #{ txoutsetinfo["bestblock"] } at height #{ txoutsetinfo["height"] } missing in blocks database"
      end
    end

    outset = TxOutset.create_with(txouts: txoutsetinfo["txouts"], total_amount: txoutsetinfo["total_amount"]).find_or_create_by(block: block)

    # TODO: Check that the previous snapshot is a block ancestor, otherwise delete it

    # TODO: Check that inflation does not exceed 12.5 BTC per block (abort this simlified check after halvening)

    # TODO: Process each block and calculate inflation; compare with snapshot.

    # TODO: Send alert if greater than allowed
  end

  def self.find_or_create_block_and_ancestors!(hash, node)
    # Not atomic and called very frequently, so sometimes it tries to insert
    # a block that was already inserted. In that case try again, so it updates
    # the existing block instead.
    begin
      block = Block.find_by(block_hash: hash)

      if block.nil?
        if node.client_type.to_sym == :libbitcoin
          block_info = node.client.getblockheader(hash)
        else
          block_info = node.client.getblock(hash)
        end

        pool = node.get_pool_for_block!(block_info["hash"], block_info)

        block = Block.create(
          coin: node.coin.downcase.to_sym,
          block_hash: block_info["hash"],
          height: block_info["height"],
          mediantime: block_info["mediantime"],
          timestamp: block_info["time"],
          work: block_info["chainwork"],
          version: block_info["version"],
          first_seen_by: node,
          pool: pool
        )

      end

      block.find_ancestors!(node)
    rescue ActiveRecord::RecordNotUnique
      raise unless Rails.env.production?
      retry
    end
    return block
  end

end

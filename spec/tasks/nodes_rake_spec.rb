# frozen_string_literal: true

require 'rails_helper'
require 'spec_helper'

# rubocop:disable RSpec/MultipleDescribes
# rubocop:disable RSpec/DescribeClass
# rubocop:disable RSpec/NamedSubject
describe 'nodes:poll' do
  include_context 'with rake'

  it 'calls :poll! on Node' do
    expect(Node).to receive(:poll!)
    subject.invoke
  end

  it 'calls :poll! on Node with a list of coins' do
    expect(Node).to receive(:poll!).with({ coins: %w[BTC TBTC] })
    subject.invoke('BTC', 'TBTC')
  end
end

describe 'nodes:poll_repeat' do
  include_context 'with rake'

  it 'calls :pollrepeat! on Node' do
    expect(Node).to receive(:poll_repeat!)
    subject.invoke
  end

  it 'calls :pollrepeat! on Node with a list of coins' do
    expect(Node).to receive(:poll_repeat!).with({ coins: %w[BTC TBTC] })
    subject.invoke('BTC', 'TBTC')
  end
end

describe 'nodes:heavy_checks_repeat' do
  include_context 'with rake'

  it 'calls :heavy_checks_repeat! on Node' do
    expect(Node).to receive(:heavy_checks_repeat!)
    subject.invoke
  end

  it 'calls :heavy_checks_repeat! on Node with a list of coins' do
    expect(Node).to receive(:heavy_checks_repeat!).with({ coins: %w[BTC TBTC] })
    subject.invoke('BTC', 'TBTC')
  end
end

describe 'nodes:rollback_checks_repeat' do
  include_context 'with rake'

  it 'calls :rollback_checks_repeat! on Node' do
    expect(Node).to receive(:rollback_checks_repeat!)
    subject.invoke
  end

  it 'calls :rollback_checks_repeat! on Node with a list of coins' do
    expect(Node).to receive(:rollback_checks_repeat!).with({ coins: %w[BTC TBTC] })
    subject.invoke('BTC', 'TBTC')
  end
end

describe 'nodes:getblocktemplate_repeat' do
  include_context 'with rake'

  it 'calls :getblocktemplate_repeat! on Node' do
    expect(Node).to receive(:getblocktemplate_repeat!)
    subject.invoke
  end

  it 'calls :getblocktemplate_repeat! on Node with a list of coins' do
    expect(Node).to receive(:getblocktemplate_repeat!).with({ coins: %w[BTC TBTC] })
    subject.invoke('BTC', 'TBTC')
  end
end
# rubocop:enable RSpec/NamedSubject
# rubocop:enable RSpec/DescribeClass
# rubocop:enable RSpec/MultipleDescribes

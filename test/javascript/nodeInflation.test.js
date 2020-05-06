import React from 'react';
import ReactDOM from 'react-dom';

import { mount, configure } from 'enzyme';
import Adapter from 'enzyme-adapter-react-16';
configure({ adapter: new Adapter() });

import NodeInflation from 'forkMonitorApp/components/nodeInflation';

let wrapper;

describe('NodeInflation', () => {

  const chaintip = {
    hash: "abcd",
    height: 500000,
    timestamp: 1,
    work: 86.000001
  }

  const txOutset = {
    id: 1,
    txouts: 63265720,
    total_amount: "17993054.82194891",
    created_at: "2019-10-15T09:42:54.919Z",
    inflated: false
  };

  const node = {
    id: 1,
    name_with_version: "Bitcoin Core 0.17.1",
    best_block: chaintip,
    unreachable_since: null,
    ibd: false,
    height: 500000 - 2,
    os: "Linux"
  };


  beforeAll(() => {
    wrapper = mount(<NodeInflation
      node={ node }
      txOutset={ txOutset }
      disableTooltip={ true } // Tooltip compoment doesn't play nicely with Jest
    />)
  });

  test('should show coin supply', () => {
    expect(wrapper.text()).toContain("17,993,054.8");
  });

  test('should show spinner if supply is being calculated', () => {
    wrapper.setProps({txOutset: null})
    expect(wrapper.exists('.fa-spinner')).toEqual(true);
  });

  test('should show "inflated" if supply is inflated', () => {
    wrapper.setProps({txOutset: {inflated: true}})
    expect(wrapper.exists('.fa-times-circle')).toEqual(true);
  });

});

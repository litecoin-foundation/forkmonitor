import React from 'react';
import ReactDOM from 'react-dom';

import { mount, configure } from 'enzyme';
import Adapter from 'enzyme-adapter-react-16';
configure({ adapter: new Adapter() });

import Node from 'forkMonitorApp/components/node';

const chaintip = {
  hash: "abcd",
  height: 500000,
  timestamp: 1,
  work: 86.000001
}

let wrapper;

describe('Node', () => {
  const node = {id: 1, name: "Bitcoin Core", version: 170100, best_block: chaintip, unreachable_since: null, ibd: false};
});

describe('Status badge', () => {
  const node = {id: 1, name: "Bitcoin Core", version: 170100, best_block: chaintip, unreachable_since: null, ibd: false};

  let wrapper;

  beforeAll(() => {
    wrapper = mount(<Node
      key={ 0 }
      node={ node }
    />)
  });

  test('should indicate when unreachable', () => {
    wrapper.setProps({node: {unreachable_since: "2019-02-14T17:54:31.959Z"}});
    expect(wrapper.find("Badge").text()).toEqual("Offline");
  });

  test('should indicate when online, but syncing', () => {
    wrapper.setProps({node: {unreachable_since: null, ibd: true}});
    expect(wrapper.find("Badge").text()).toEqual("Syncing");
  });

  test('should indicate when online', () => {
    wrapper.setProps({node: {unreachable_since: null, ibd: false}});
    expect(wrapper.find("Badge").text()).toEqual("Online");
  });

});

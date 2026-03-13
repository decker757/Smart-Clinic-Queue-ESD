import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import { createRouter, createMemoryHistory } from 'vue-router'
import { createPinia } from 'pinia'
import App from '../App.vue'

const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/', component: { template: '<div>home</div>' } }],
})

describe('App', () => {
  it('mounts with router', async () => {
    const wrapper = mount(App, { global: { plugins: [router, createPinia()] } })
    await router.isReady()
    expect(wrapper.exists()).toBe(true)
  })
})

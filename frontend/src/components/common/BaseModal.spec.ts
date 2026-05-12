import { describe, it, expect } from 'vitest'
import { mount } from '@vue/test-utils'
import BaseModal from './BaseModal.vue'

// BaseModal leans on native <dialog>, which gives focus trapping, Escape-close
// and an inert background out of the box. These tests cover the Vue-side
// wiring only: that the component emits close on the right events and that
// preventClose suppresses both routes. The browser-side guarantee that
// Escape actually fires `cancel` and the dialog's own `.close()` actually
// fires `close` isn't exercised here — jsdom stubs both — so the end-to-end
// open/close interaction is covered by e2e/tests/design-system.spec.ts.
describe('BaseModal', () => {
  const baseProps = { open: true, title: 'Confirm delete' }

  function dispatchOn(wrapper: ReturnType<typeof mount>, eventName: string) {
    const dialog = wrapper.get('dialog').element
    dialog.dispatchEvent(new Event(eventName))
  }

  it('emits close when the dialog fires its native close event (Escape)', () => {
    const wrapper = mount(BaseModal, { props: baseProps })
    dispatchOn(wrapper, 'close')
    expect(wrapper.emitted('close')).toHaveLength(1)
  })

  it('emits close when the X button is clicked', async () => {
    const wrapper = mount(BaseModal, { props: baseProps })
    await wrapper.get('button').trigger('click')
    expect(wrapper.emitted('close')).toHaveLength(1)
  })

  describe('with preventClose', () => {
    it('does not emit close when the dialog fires close', () => {
      const wrapper = mount(BaseModal, {
        props: { ...baseProps, preventClose: true },
      })
      dispatchOn(wrapper, 'close')
      expect(wrapper.emitted('close')).toBeUndefined()
    })

    it('disables the X button so it cannot dismiss the modal', () => {
      const wrapper = mount(BaseModal, {
        props: { ...baseProps, preventClose: true },
      })
      expect(wrapper.get('button').attributes('disabled')).toBeDefined()
    })

    it('cancels the native cancel event so Escape does not close', () => {
      const wrapper = mount(BaseModal, {
        props: { ...baseProps, preventClose: true },
      })
      const dialog = wrapper.get('dialog').element
      const event = new Event('cancel', { cancelable: true })
      dialog.dispatchEvent(event)
      expect(event.defaultPrevented).toBe(true)
    })
  })
})

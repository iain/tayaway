import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { mount, flushPromises, VueWrapper } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import PasskeysList from './PasskeysList.vue'
import type { Passkey } from '@/types'

const mockListPasskeys = vi.fn()
const mockRegisterPasskey = vi.fn()
const mockRenamePasskey = vi.fn()
const mockDeletePasskey = vi.fn()

vi.mock('@/stores/auth', () => ({
  useAuthStore: () => ({
    listPasskeys: mockListPasskeys,
    registerPasskey: mockRegisterPasskey,
    renamePasskey: mockRenamePasskey,
    deletePasskey: mockDeletePasskey,
  }),
}))

const mockShowInfo = vi.fn()
vi.mock('@/stores', () => ({
  useNotificationsStore: () => ({
    showInfo: mockShowInfo,
  }),
}))

const fakePasskey: Passkey = {
  id: 'pk-1',
  name: 'MacBook',
  aaguid: null,
  createdAt: '2026-01-01T00:00:00Z',
}

function findByText(wrapper: VueWrapper, selector: string, text: string) {
  return wrapper.findAll(selector).find((el) => el.text().includes(text))
}

describe('PasskeysList', () => {
  beforeEach(() => {
    vi.useFakeTimers()
    setActivePinia(createPinia())
    mockListPasskeys.mockResolvedValue([fakePasskey])
    mockDeletePasskey.mockResolvedValue(undefined)
    mockRenamePasskey.mockResolvedValue(fakePasskey)
  })

  afterEach(() => {
    vi.useRealTimers()
    vi.restoreAllMocks()
  })

  async function mountAndLoad() {
    const wrapper = mount(PasskeysList, {
      global: {
        stubs: {
          BaseModal: {
            template: '<div v-if="open" data-testid="modal"><slot /></div>',
            props: ['open', 'title', 'preventClose'],
            emits: ['close'],
          },
          FormInput: {
            template:
              '<input :id="id" :value="modelValue" @input="$emit(\'update:modelValue\', $event.target.value)" />',
            props: [
              'id',
              'modelValue',
              'label',
              'placeholder',
              'maxlength',
              'required',
              'disabled',
            ],
            emits: ['update:modelValue'],
          },
          FormActions: {
            template:
              '<div><button type="button" data-role="cancel" @click="$emit(\'cancel\')">Cancel</button><button type="submit" :disabled="disabled">{{ submitLabel }}</button></div>',
            props: ['submitLabel', 'loading', 'disabled'],
            emits: ['cancel'],
          },
        },
      },
    })
    await flushPromises()
    return wrapper
  }

  it('shows passkeys after loading', async () => {
    const wrapper = await mountAndLoad()
    expect(wrapper.text()).toContain('MacBook')
  })

  it('shows error when loading fails', async () => {
    mockListPasskeys.mockRejectedValue(new Error('fail'))
    const wrapper = await mountAndLoad()
    expect(wrapper.text()).toContain('Could not load passkeys')
  })

  it('shows empty state when no passkeys', async () => {
    mockListPasskeys.mockResolvedValue([])
    const wrapper = await mountAndLoad()
    expect(wrapper.text()).toContain('No passkeys registered')
  })

  async function openModalAndContinue(wrapper: VueWrapper) {
    // Click "Add passkey" button
    const addBtn = findByText(wrapper, 'button', 'Add passkey')
    expect(addBtn).toBeTruthy()
    await addBtn!.trigger('click')
    await flushPromises()

    // Click "Continue" button
    const continueBtn = findByText(wrapper, 'button', 'Continue')
    expect(continueBtn).toBeTruthy()
    await continueBtn!.trigger('click')
    await flushPromises()
  }

  describe('registration — InvalidStateError', () => {
    it('shows error message instead of spinner', async () => {
      const wrapper = await mountAndLoad()

      const error = new Error('already registered')
      error.name = 'InvalidStateError'
      mockRegisterPasskey.mockRejectedValue(error)

      await openModalAndContinue(wrapper)

      // Should show the error message, not the spinner
      expect(wrapper.text()).toContain('already registered')
      expect(wrapper.text()).not.toContain('Follow your browser')
    })
  })

  describe('registration — generic error', () => {
    it('shows generic error message', async () => {
      const wrapper = await mountAndLoad()
      mockRegisterPasskey.mockRejectedValue(new Error('network fail'))

      await openModalAndContinue(wrapper)

      expect(wrapper.text()).toContain('Failed to register passkey')
    })
  })

  describe('cancel during name step deletes passkey', () => {
    it('calls deletePasskey on cancel', async () => {
      const createdPasskey = { ...fakePasskey, id: 'pk-new' }
      mockRegisterPasskey.mockResolvedValue(createdPasskey)

      const wrapper = await mountAndLoad()
      await openModalAndContinue(wrapper)

      // Now at name step — click the cancel button rendered by FormActions stub
      const cancelBtn = wrapper.find('[data-role="cancel"]')
      expect(cancelBtn.exists()).toBe(true)
      await cancelBtn.trigger('click')
      await flushPromises()

      expect(mockDeletePasskey).toHaveBeenCalledWith('pk-new')
    })
  })

  describe('delete with undo', () => {
    it('removes passkey from list and restores on undo', async () => {
      const wrapper = await mountAndLoad()
      expect(wrapper.text()).toContain('MacBook')

      // Click delete button (button with trash icon / "Delete passkey" label)
      const deleteBtn = findByText(wrapper, 'button', 'Delete passkey')
      expect(deleteBtn).toBeTruthy()
      await deleteBtn!.trigger('click')

      // Passkey should be removed from the list
      expect(wrapper.text()).not.toContain('MacBook')
      expect(mockShowInfo).toHaveBeenCalledWith(
        'Passkey removed',
        expect.objectContaining({ actionLabel: 'Undo' })
      )

      // Call the undo action
      const undoCall = mockShowInfo.mock.calls[0]
      undoCall[1].action()
      await flushPromises()

      // Passkey should be restored
      expect(wrapper.text()).toContain('MacBook')
    })

    it('executes delete after timer expires', async () => {
      const wrapper = await mountAndLoad()

      const deleteBtn = findByText(wrapper, 'button', 'Delete passkey')
      await deleteBtn!.trigger('click')

      // Fast-forward past the undo delay
      vi.advanceTimersByTime(4000)
      await flushPromises()

      expect(mockDeletePasskey).toHaveBeenCalledWith('pk-1')
    })
  })

  describe('rename with rollback', () => {
    it('reverts optimistic update on API failure', async () => {
      mockRenamePasskey.mockRejectedValue(new Error('rename failed'))

      const wrapper = await mountAndLoad()

      // Click rename button
      const renameBtn = findByText(wrapper, 'button', 'Rename passkey')
      expect(renameBtn).toBeTruthy()
      await renameBtn!.trigger('click')
      await flushPromises()

      // Find the rename input and change the value
      const input = wrapper.find('input[type="text"]')
      await input.setValue('New Name')
      await wrapper.find('form').trigger('submit')
      await flushPromises()

      // After API failure, should revert to original name
      expect(wrapper.text()).toContain('MacBook')
    })
  })
})

import { describe, it, expect, beforeEach } from 'vitest'
import { mount } from '@vue/test-utils'
import { createPinia, setActivePinia } from 'pinia'
import { useAuthStore } from '@/stores/auth'
import { formatDateDisplay } from '@/utils/date'
import SettingsProfilePage from './SettingsProfilePage.vue'

function signIn(birthday: string | null = null): void {
  useAuthStore().user = {
    id: 'user-1',
    email: 'user-1@example.com',
    name: 'Test',
    phoneNumber: null,
    birthday,
    locationName: null,
    latitude: null,
    longitude: null,
    iban: null,
    ibanHolderName: null,
    timezone: null,
  }
}

describe('SettingsProfilePage', () => {
  beforeEach(() => {
    setActivePinia(createPinia())
    localStorage.clear()
  })

  // The native date input renders in the browser's locale, which the app
  // cannot control — someone thinking DD/MM can type Feb 8 into an MM/DD
  // field and get Aug 2. The preview spells the month out so the mistake is
  // visible before it is saved.
  it('previews the picked birthday with the month spelled out', async () => {
    signIn()
    const page = mount(SettingsProfilePage)

    await page.find('[data-testid="edit-birthday-button"]').trigger('click')
    await page.find('input[type="date"]').setValue('1990-08-02')

    expect(page.find('[data-testid="birthday-preview"]').text()).toBe(
      formatDateDisplay('1990-08-02')
    )
  })
})

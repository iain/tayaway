import {
  addDays,
  monthGridDays,
  nextMondayAfter,
  formatDateDisplay as _formatDateDisplay,
  getMonthName as _getMonthName,
} from '@/utils/date'
import { useLocale } from './useLocale'

export type { CalendarDay } from '@/utils/date'
export { formatDateDisplay, getMonthName } from '@/utils/date'

export function useCalendar() {
  const { locale } = useLocale()

  function isDateInRange(
    dateString: string,
    startString: string | null,
    endString: string | null
  ): boolean {
    if (!startString || !endString) return false
    return dateString >= startString && dateString <= endString
  }

  function isDateInHoverRange(
    dateString: string,
    startString: string | null,
    hoverString: string | null
  ): boolean {
    if (!startString || !hoverString) return false
    const start = startString < hoverString ? startString : hoverString
    const end = startString < hoverString ? hoverString : startString
    return dateString >= start && dateString <= end
  }

  // Locale-bound wrappers so calendar consumers automatically pick up the
  // viewer's own date/time format instead of one fixed locale for everyone.
  // The unbound `formatDateDisplay`/`getMonthName` re-exports above remain
  // for one-shot, non-reactive callers that pass their own locale explicitly.
  function formatDateDisplay(dateString: string): string {
    return _formatDateDisplay(dateString, locale.value)
  }

  function getMonthName(month: number): string {
    return _getMonthName(month, locale.value)
  }

  return {
    getDaysInMonth: monthGridDays,
    isDateInRange,
    isDateInHoverRange,
    getNextMonday: nextMondayAfter,
    addDays,
    getMonthName,
    formatDateDisplay,
  }
}

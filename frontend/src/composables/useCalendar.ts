export interface CalendarDay {
  date: Date
  isCurrentMonth: boolean
  dateString: string
}

import {
  addDays,
  formatDateDisplay as _formatDateDisplay,
  getMonthName as _getMonthName,
} from '@/utils/date'

export { formatDateDisplay, getMonthName } from '@/utils/date'

export function useCalendar() {
  function getDaysInMonth(year: number, month: number): CalendarDay[] {
    const days: CalendarDay[] = []
    const firstDay = new Date(year, month, 1)
    const lastDay = new Date(year, month + 1, 0)

    // Get the day of week for the first day (0 = Sunday, 1 = Monday, etc.)
    // Adjust to start week on Monday (0 = Monday, 6 = Sunday)
    let startOffset = firstDay.getDay() - 1
    if (startOffset < 0) startOffset = 6

    // Add days from previous month to fill the first week
    for (let i = startOffset - 1; i >= 0; i--) {
      const date = new Date(year, month, -i)
      days.push({
        date,
        isCurrentMonth: false,
        dateString: formatDate(date),
      })
    }

    // Add days of current month
    for (let day = 1; day <= lastDay.getDate(); day++) {
      const date = new Date(year, month, day)
      days.push({
        date,
        isCurrentMonth: true,
        dateString: formatDate(date),
      })
    }

    // Add days from next month to complete the grid (6 rows of 7 days)
    const remainingDays = 42 - days.length
    for (let i = 1; i <= remainingDays; i++) {
      const date = new Date(year, month + 1, i)
      days.push({
        date,
        isCurrentMonth: false,
        dateString: formatDate(date),
      })
    }

    return days
  }

  function formatDate(date: Date): string {
    const year = date.getFullYear()
    const month = String(date.getMonth() + 1).padStart(2, '0')
    const day = String(date.getDate()).padStart(2, '0')
    return `${year}-${month}-${day}`
  }

  function parseDate(dateString: string): Date {
    const [year, month, day] = dateString.split('-').map(Number) as [
      number,
      number,
      number,
    ]
    return new Date(year, month - 1, day)
  }

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

  function getNextMonday(afterDateString: string): string {
    const date = parseDate(afterDateString)
    // Move to next day
    date.setDate(date.getDate() + 1)
    // Find next Monday
    const dayOfWeek = date.getDay()
    const daysUntilMonday = dayOfWeek === 0 ? 1 : (8 - dayOfWeek) % 7 || 7
    date.setDate(date.getDate() + daysUntilMonday)
    return formatDate(date)
  }

  return {
    getDaysInMonth,
    formatDate,
    parseDate,
    isDateInRange,
    isDateInHoverRange,
    getNextMonday,
    addDays,
    getMonthName: _getMonthName,
    formatDateDisplay: _formatDateDisplay,
  }
}

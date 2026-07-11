export interface Notification {
  id: string
  type: 'error' | 'info'
  message: string
  action?: () => void | Promise<void>
  actionLabel?: string
}

export interface Notification {
  id: string
  type: 'error' | 'info' | 'update'
  message: string
  action?: () => void
}

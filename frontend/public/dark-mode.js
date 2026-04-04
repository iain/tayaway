// Detect dark mode preference before Vue loads to prevent flash of wrong theme.
// This runs synchronously in <head> before any rendering.
;(function () {
  var saved = localStorage.getItem('dark_mode')
  var systemDark = window.matchMedia('(prefers-color-scheme: dark)').matches
  var isDark = saved === 'dark' || (saved !== 'light' && systemDark)
  if (isDark) document.documentElement.classList.add('dark')
})()

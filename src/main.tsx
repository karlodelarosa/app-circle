import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import { registerSW } from 'virtual:pwa-register'
import App from './App'
import { AppProvider } from './AppContext'
import './styles.css'

window.__circlesUpdateSW = registerSW({
  immediate: true,
  onNeedRefresh() {
    window.__circlesUpdatePending = true
    window.dispatchEvent(new Event('circles:pwa-update'))
  },
})

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode><BrowserRouter><AppProvider><App /></AppProvider></BrowserRouter></React.StrictMode>
)

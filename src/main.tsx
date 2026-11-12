import React from 'react'
import ReactDOM from 'react-dom/client'
import type { Session } from '@supabase/supabase-js'
import { BrowserRouter } from 'react-router-dom'
import { registerSW } from 'virtual:pwa-register'
import App from './App'
import { AppProvider } from './AppContext'
import { ErrorBoundary } from './components/ErrorBoundary'
import { demoData } from './data/demo'
import { isDemoDeployment } from './lib/supabase'
import './styles.css'

window.__circlesUpdateSW = registerSW({
  immediate: true,
  onNeedRefresh() {
    window.__circlesUpdatePending = true
    window.dispatchEvent(new Event('circles:pwa-update'))
  },
})

const demoSession = isDemoDeployment ? ({
  access_token: 'demo', refresh_token: 'demo', expires_in: 3600, token_type: 'bearer',
  user: { id: 'demo-user', email: 'karlo@example.com' },
} as Session) : null

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode><ErrorBoundary><BrowserRouter><AppProvider initialData={isDemoDeployment ? demoData : null} initialSession={demoSession}><App /></AppProvider></BrowserRouter></ErrorBoundary></React.StrictMode>
)

import { createClient, type SupabaseClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_OR_ANON_KEY as string | undefined

export const isSupabaseConfigured = Boolean(url && anonKey)

// This is the app's only Supabase client. If Circles is later mounted inside a
// host app, replace this export with the host's shared client import.
export const supabase: SupabaseClient | null = isSupabaseConfigured
  ? createClient(url!, anonKey!, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    })
  : null

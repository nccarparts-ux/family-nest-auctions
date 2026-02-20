/**
 * Family Nest Auctions — Frontend API Client
 * Drop this file into your repo as: /js/api.js
 * Add to every HTML page: <script src="/js/api.js"></script>
 * 
 * Handles: Auth, real-time bidding, watchlist, payments, search
 */

// ── CONFIG — replace with your actual Supabase project values ──────────────
const SUPABASE_URL = 'https://YOUR_PROJECT.supabase.co'
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY'
const SITE_URL = window.location.origin

// ── LOAD SUPABASE SDK ────────────────────────────────────────────────────────
// Add to your HTML <head>:
// <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js"></script>

let supabase = null

function initSupabase() {
  if (window.supabase && !supabase) {
    supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true }
    })
  }
  return supabase
}

// ── AUTH ─────────────────────────────────────────────────────────────────────

const Auth = {
  async signUp({ email, password, fullName }) {
    const sb = initSupabase()
    const { data, error } = await sb.auth.signUp({
      email, password,
      options: { data: { full_name: fullName } }
    })
    if (error) throw error
    // Profile is auto-created via Supabase trigger
    return data
  },

  async signIn({ email, password }) {
    const sb = initSupabase()
    const { data, error } = await sb.auth.signInWithPassword({ email, password })
    if (error) throw error
    return data
  },

  async signOut() {
    const sb = initSupabase()
    await sb.auth.signOut()
    window.location.href = '/family-nest-auctions.html'
  },

  async getUser() {
    const sb = initSupabase()
    const { data: { user } } = await sb.auth.getUser()
    return user
  },

  async getSession() {
    const sb = initSupabase()
    const { data: { session } } = await sb.auth.getSession()
    return session
  },

  onAuthStateChange(callback) {
    const sb = initSupabase()
    return sb.auth.onAuthStateChange(callback)
  },

  async requireAuth() {
    const user = await Auth.getUser()
    if (!user) {
      window.location.href = '/family-nest-auctions.html?login=1'
      return null
    }
    return user
  }
}

// ── ITEMS / AUCTIONS ─────────────────────────────────────────────────────────

const Items = {
  async getAll({ category, status = 'live', search, sort = 'ends_at', limit = 24, offset = 0 } = {}) {
    const sb = initSupabase()
    let query = sb
      .from('items')
      .select(`
        id, title, description, category, condition, current_bid,
        bid_count, view_count, ends_at, status, starting_bid,
        buyers_premium_pct, est_shipping_min, est_shipping_max,
        item_number, created_at,
        item_photos (storage_url, is_primary, display_order),
        sellers (id, business_name, avg_rating)
      `)
      .eq('status', status)
      .order(sort, { ascending: sort === 'current_bid' ? true : true })
      .range(offset, offset + limit - 1)

    if (category && category !== 'all') query = query.eq('category', category)
    if (search) query = query.textSearch('title', search, { type: 'websearch' })

    const { data, error, count } = await query
    if (error) throw error
    return { items: data, count }
  },

  async getById(id) {
    const sb = initSupabase()
    const { data, error } = await sb
      .from('items')
      .select(`
        *,
        item_photos (storage_url, is_primary, display_order, caption),
        sellers (id, business_name, avg_rating, total_reviews, total_sales),
        estate_sales (id, name, location_city, location_state)
      `)
      .eq('id', id)
      .single()
    if (error) throw error

    // Increment view count (non-blocking)
    sb.rpc('increment_view_count', { p_item_id: id }).catch(() => {})

    return data
  },

  async getBidHistory(itemId, limit = 20) {
    const sb = initSupabase()
    const { data, error } = await sb
      .from('bids')
      .select('amount, created_at, is_proxy')
      .eq('item_id', itemId)
      .order('created_at', { ascending: false })
      .limit(limit)
    if (error) throw error
    return data
  },

  // Subscribe to real-time bid updates on a specific item
  subscribeToItem(itemId, onUpdate) {
    const sb = initSupabase()
    const subscription = sb
      .channel(`item:${itemId}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'items',
        filter: `id=eq.${itemId}`,
      }, (payload) => onUpdate(payload.new))
      .subscribe()
    return () => sb.removeChannel(subscription)
  },

  // Subscribe to new bids on an item
  subscribeToBids(itemId, onNewBid) {
    const sb = initSupabase()
    const subscription = sb
      .channel(`bids:${itemId}`)
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'bids',
        filter: `item_id=eq.${itemId}`,
      }, (payload) => onNewBid(payload.new))
      .subscribe()
    return () => sb.removeChannel(subscription)
  }
}

// ── BIDDING ──────────────────────────────────────────────────────────────────

const Bidding = {
  async placeBid(itemId, amount, maxAmount = null) {
    const session = await Auth.getSession()
    if (!session) throw new Error('Please sign in to bid')

    const response = await fetch(`${SUPABASE_URL}/functions/v1/place-bid`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ item_id: itemId, amount, max_amount: maxAmount }),
    })

    const result = await response.json()
    if (!result.success) throw new Error(result.error)
    return result
  },

  async getMyBids(status = 'active') {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) return []

    const { data, error } = await sb
      .from('bids')
      .select(`
        id, amount, max_amount, is_winning, created_at,
        items (
          id, title, current_bid, ends_at, status, current_bidder_id,
          item_photos (storage_url, is_primary)
        )
      `)
      .eq('bidder_id', user.id)
      .eq('is_winning', true)
      .order('created_at', { ascending: false })

    if (error) throw error
    return data
  }
}

// ── WATCHLIST ────────────────────────────────────────────────────────────────

const Watchlist = {
  async getAll() {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) return []

    const { data, error } = await sb
      .from('watchlist')
      .select(`
        item_id,
        items (
          id, title, current_bid, ends_at, status, bid_count,
          item_photos (storage_url, is_primary)
        )
      `)
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })

    if (error) throw error
    return data
  },

  async toggle(itemId) {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) throw new Error('Sign in to save items')

    // Check if already watching
    const { data: existing } = await sb
      .from('watchlist')
      .select('id')
      .eq('user_id', user.id)
      .eq('item_id', itemId)
      .maybeSingle()

    if (existing) {
      await sb.from('watchlist').delete().eq('id', existing.id)
      return { watching: false }
    } else {
      await sb.from('watchlist').insert({ user_id: user.id, item_id: itemId })
      return { watching: true }
    }
  },

  async isWatching(itemId) {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) return false

    const { data } = await sb
      .from('watchlist')
      .select('id')
      .eq('user_id', user.id)
      .eq('item_id', itemId)
      .maybeSingle()

    return !!data
  }
}

// ── PAYMENTS ─────────────────────────────────────────────────────────────────

const Payments = {
  async createPaymentIntent(orderId) {
    const session = await Auth.getSession()
    if (!session) throw new Error('Not authenticated')

    const response = await fetch(`${SUPABASE_URL}/functions/v1/create-payment-intent`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ order_id: orderId }),
    })

    const result = await response.json()
    if (result.error) throw new Error(result.error)
    return result
  },

  async getMyOrders() {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) return []

    const { data, error } = await sb
      .from('orders')
      .select(`
        id, winning_bid, buyers_premium, total_charged, payment_status,
        shipping_status, tracking_number, carrier, created_at,
        items (id, title, item_photos (storage_url, is_primary)),
        sellers (business_name)
      `)
      .eq('buyer_id', user.id)
      .order('created_at', { ascending: false })

    if (error) throw error
    return data
  }
}

// ── SEARCH ───────────────────────────────────────────────────────────────────

const Search = {
  async fullText(query, { category, condition, minPrice, maxPrice, sort, limit = 24 } = {}) {
    const sb = initSupabase()
    let q = sb
      .from('items')
      .select(`
        id, title, current_bid, bid_count, ends_at, category, condition,
        est_shipping_min, buyers_premium_pct,
        item_photos (storage_url, is_primary),
        sellers (business_name, avg_rating)
      `)
      .eq('status', 'live')
      .limit(limit)

    if (query) q = q.textSearch('title', query, { type: 'websearch' })
    if (category && category !== 'all') q = q.eq('category', category)
    if (condition) q = q.eq('condition', condition)
    if (minPrice) q = q.gte('current_bid', minPrice)
    if (maxPrice) q = q.lte('current_bid', maxPrice)
    if (sort === 'ending_soon') q = q.order('ends_at', { ascending: true })
    if (sort === 'price_low') q = q.order('current_bid', { ascending: true })
    if (sort === 'price_high') q = q.order('current_bid', { ascending: false })
    if (sort === 'most_bids') q = q.order('bid_count', { ascending: false })

    const { data, error, count } = await q
    if (error) throw error
    return { results: data, count }
  }
}

// ── NOTIFICATIONS ────────────────────────────────────────────────────────────

const Notifications = {
  async getAll(limit = 20) {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) return []

    const { data, error } = await sb
      .from('notifications')
      .select('*')
      .eq('user_id', user.id)
      .order('created_at', { ascending: false })
      .limit(limit)

    if (error) throw error
    return data
  },

  async markAllRead() {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) return

    await sb
      .from('notifications')
      .update({ is_read: true })
      .eq('user_id', user.id)
      .eq('is_read', false)
  },

  subscribeToNew(onNotification) {
    const sb = initSupabase()
    let userId = null
    Auth.getUser().then(u => { userId = u?.id })

    const subscription = sb
      .channel('notifications')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'notifications',
      }, (payload) => {
        if (payload.new.user_id === userId) {
          onNotification(payload.new)
        }
      })
      .subscribe()

    return () => sb.removeChannel(subscription)
  }
}

// ── STORAGE (photos) ─────────────────────────────────────────────────────────

const Storage = {
  async uploadItemPhoto(file, itemId, displayOrder = 0) {
    const sb = initSupabase()
    const user = await Auth.getUser()
    if (!user) throw new Error('Not authenticated')

    const ext = file.name.split('.').pop()
    const path = `items/${itemId}/${Date.now()}_${displayOrder}.${ext}`

    const { data, error } = await sb.storage
      .from('item-photos')
      .upload(path, file, { contentType: file.type, upsert: false })

    if (error) throw error

    const { data: { publicUrl } } = sb.storage.from('item-photos').getPublicUrl(path)

    // Save to item_photos table
    await sb.from('item_photos').insert({
      item_id: itemId,
      storage_url: publicUrl,
      display_order: displayOrder,
      is_primary: displayOrder === 0,
    })

    return publicUrl
  }
}

// ── UI HELPERS ───────────────────────────────────────────────────────────────

const UI = {
  // Format price with buyer's premium breakdown
  formatPriceBreakdown(currentBid, premiumPct = 15, shippingMin = 0, shippingMax = 0) {
    const premium = currentBid * premiumPct / 100
    const total = currentBid + premium + ((shippingMin + shippingMax) / 2 || 0)
    return {
      bid: currentBid,
      premium: premium.toFixed(2),
      shipping: shippingMin ? `$${shippingMin}–$${shippingMax}` : 'TBD',
      total: total.toFixed(2),
    }
  },

  // Format countdown
  formatCountdown(endsAt) {
    const diff = new Date(endsAt) - Date.now()
    if (diff <= 0) return { text: 'Ended', urgent: false }

    const days = Math.floor(diff / 86400000)
    const hours = Math.floor((diff % 86400000) / 3600000)
    const mins = Math.floor((diff % 3600000) / 60000)
    const secs = Math.floor((diff % 60000) / 1000)

    const urgent = diff < 3600000  // < 1 hour
    let text
    if (days > 0) text = `${days}d ${hours}h`
    else if (hours > 0) text = `${hours}h ${mins}m`
    else text = `${mins}m ${secs}s`

    return { text, urgent }
  },

  // Update all countdown elements on a page
  startCountdowns() {
    setInterval(() => {
      document.querySelectorAll('[data-ends-at]').forEach(el => {
        const { text, urgent } = UI.formatCountdown(el.dataset.endsAt)
        el.textContent = text
        el.classList.toggle('urgent', urgent)
      })
    }, 1000)
  },

  // Show a toast notification
  toast(message, title = '', type = 'default') {
    const t = document.getElementById('the-toast')
    if (!t) return
    const ttl = document.getElementById('t-ttl')
    const msg = document.getElementById('t-msg')
    if (ttl) ttl.textContent = title
    if (msg) msg.textContent = message
    t.classList.add('on')
    setTimeout(() => t.classList.remove('on'), 3400)
  },

  // Check if user is logged in and update nav accordingly
  async updateNavForAuth() {
    const user = await Auth.getUser()
    const signInBtns = document.querySelectorAll('[data-auth="signin"]')
    const accountBtns = document.querySelectorAll('[data-auth="account"]')
    const userDisplays = document.querySelectorAll('[data-auth="name"]')

    if (user) {
      signInBtns.forEach(b => b.style.display = 'none')
      accountBtns.forEach(b => b.style.display = '')
      const profile = await supabase.from('profiles').select('display_name,full_name').eq('id', user.id).single()
      const name = profile.data?.display_name || profile.data?.full_name || user.email
      userDisplays.forEach(el => el.textContent = name)
    } else {
      signInBtns.forEach(b => b.style.display = '')
      accountBtns.forEach(b => b.style.display = 'none')
    }
  }
}

// ── INIT ─────────────────────────────────────────────────────────────────────
document.addEventListener('DOMContentLoaded', async () => {
  try {
    initSupabase()
    await UI.updateNavForAuth()
    UI.startCountdowns()

    // If page has ?login=1, open login modal
    if (new URLSearchParams(window.location.search).get('login') === '1') {
      if (typeof openOv === 'function') openOv('login')
    }
  } catch (e) {
    console.warn('API init error:', e)
  }
})

// Export for use from inline scripts
window.FNA = { Auth, Items, Bidding, Watchlist, Payments, Search, Notifications, Storage, UI }

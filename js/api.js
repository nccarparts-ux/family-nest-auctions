/**
 * Family Nest Auctions — Frontend API Client
 * Supabase project: hwsjgclteuezauveujit
 */

const SUPABASE_URL = 'https://hwsjgclteuezauveujit.supabase.co'
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh3c2pnY2x0ZXVlemF1dmV1aml0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE1NDg2MzcsImV4cCI6MjA4NzEyNDYzN30.DGMw527z7noRafOxJRdGB3ITSq1teQeS5dTSNwLqFsI'
const SITE_URL = window.location.origin

// ── INIT ─────────────────────────────────────────────────────
let _sb = null
function sb() {
  if (!_sb) {
    _sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true }
    })
  }
  return _sb
}

// ── AUTH ─────────────────────────────────────────────────────
const Auth = {
  async signUp({ email, password, fullName }) {
    const { data, error } = await sb().auth.signUp({
      email, password,
      options: { data: { full_name: fullName } }
    })
    if (error) throw error
    return data
  },

  async signIn({ email, password }) {
    const { data, error } = await sb().auth.signInWithPassword({ email, password })
    if (error) throw error
    return data
  },

  async signOut() {
    await sb().auth.signOut()
    window.location.href = '/family-nest-auctions.html'
  },

  async getUser() {
    const { data: { user } } = await sb().auth.getUser()
    return user
  },

  async getSession() {
    const { data: { session } } = await sb().auth.getSession()
    return session
  },

  onAuthStateChange(cb) {
    return sb().auth.onAuthStateChange(cb)
  }
}

// ── ITEMS ─────────────────────────────────────────────────────
const Items = {
  async getLive({ category, search, sort = 'ends_at', limit = 24, offset = 0 } = {}) {
    let query = sb()
      .from('items')
      .select(`
        id, title, description, category, condition,
        current_bid, starting_bid, bid_count, view_count,
        ends_at, starts_at, status, item_number,
        buyers_premium_pct, est_shipping_min, est_shipping_max,
        seller_id,
        item_photos (storage_url, is_primary),
        sellers (id, business_name, avg_rating, city, state)
      `)
      .eq('status', 'live')
      .order(sort, { ascending: true })
      .range(offset, offset + limit - 1)

    if (category && category !== 'All') query = query.eq('category', category)
    if (search) query = query.ilike('title', `%${search}%`)

    const { data, error, count } = await query
    if (error) { console.error('getLive error:', error); return [] }
    return data || []
  },

  async getById(id) {
    const { data, error } = await sb()
      .from('items')
      .select(`
        *,
        item_photos (storage_url, is_primary, display_order, caption),
        sellers (id, business_name, avg_rating, total_reviews, total_sales, city, state),
        estate_sales (id, name, location_city, location_state)
      `)
      .eq('id', id)
      .single()
    if (error) { console.error('getById error:', error); return null }
    // Increment view count
    sb().rpc('increment_view_count', { p_item_id: id }).catch(() => {})
    return data
  },

  async getBidHistory(itemId) {
    const { data, error } = await sb()
      .from('bids')
      .select('amount, created_at, is_proxy')
      .eq('item_id', itemId)
      .order('created_at', { ascending: false })
      .limit(20)
    if (error) return []
    return data || []
  },

  subscribeToItem(itemId, onUpdate) {
    const channel = sb()
      .channel(`item-${itemId}`)
      .on('postgres_changes', {
        event: 'UPDATE',
        schema: 'public',
        table: 'items',
        filter: `id=eq.${itemId}`
      }, payload => onUpdate(payload.new))
      .subscribe()
    return () => sb().removeChannel(channel)
  }
}

// ── BIDDING ───────────────────────────────────────────────────
const Bidding = {
  async placeBid(itemId, amount, maxAmount = null) {
    const session = await Auth.getSession()
    if (!session) throw new Error('Please sign in to bid')

    const res = await fetch(`${SUPABASE_URL}/functions/v1/place-bid`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`
      },
      body: JSON.stringify({ item_id: itemId, amount, max_amount: maxAmount })
    })
    const result = await res.json()
    if (!result.success) throw new Error(result.error)
    return result
  },

  async getMyActiveBids() {
    const user = await Auth.getUser()
    if (!user) return []
    const { data } = await sb()
      .from('bids')
      .select(`
        id, amount, is_winning, created_at,
        items (id, title, current_bid, ends_at, status, current_bidder_id,
          item_photos (storage_url, is_primary))
      `)
      .eq('bidder_id', user.id)
      .eq('is_winning', true)
      .order('created_at', { ascending: false })
    return data || []
  }
}

// ── WATCHLIST ─────────────────────────────────────────────────
const Watchlist = {
  async toggle(itemId) {
    const user = await Auth.getUser()
    if (!user) { window.location.href = '/family-nest-auctions.html?login=1'; return }
    const { data: existing } = await sb()
      .from('watchlist')
      .select('id')
      .eq('user_id', user.id)
      .eq('item_id', itemId)
      .maybeSingle()
    if (existing) {
      await sb().from('watchlist').delete().eq('id', existing.id)
      return false
    } else {
      await sb().from('watchlist').insert({ user_id: user.id, item_id: itemId })
      return true
    }
  },

  async getAll() {
    const user = await Auth.getUser()
    if (!user) return []
    const { data } = await sb()
      .from('watchlist')
      .select(`item_id, items (id, title, current_bid, ends_at, status,
        item_photos (storage_url, is_primary))`)
      .eq('user_id', user.id)
    return data || []
  }
}

// ── SELLER ────────────────────────────────────────────────────
const Seller = {
  async createItem(itemData) {
    const user = await Auth.getUser()
    if (!user) throw new Error('Not authenticated')

    // Get seller record
    const { data: seller } = await sb()
      .from('sellers')
      .select('id')
      .eq('user_id', user.id)
      .single()

    if (!seller) throw new Error('No seller account found. Please contact support.')

    const { data, error } = await sb()
      .from('items')
      .insert({
        seller_id: seller.id,
        title: itemData.title,
        description: itemData.description,
        category: itemData.category,
        condition: itemData.condition,
        condition_notes: itemData.conditionNotes,
        period: itemData.period,
        starting_bid: parseFloat(itemData.startingBid),
        reserve_price: itemData.reservePrice ? parseFloat(itemData.reservePrice) : null,
        est_shipping_min: itemData.shippingMin ? parseFloat(itemData.shippingMin) : null,
        est_shipping_max: itemData.shippingMax ? parseFloat(itemData.shippingMax) : null,
        starts_at: itemData.startsAt,
        ends_at: itemData.endsAt,
        status: itemData.status || 'draft'
      })
      .select()
      .single()

    if (error) throw error
    return data
  },

  async getMyListings() {
    const user = await Auth.getUser()
    if (!user) return []
    const { data: seller } = await sb()
      .from('sellers')
      .select('id')
      .eq('user_id', user.id)
      .single()
    if (!seller) return []
    const { data } = await sb()
      .from('items')
      .select(`*, item_photos (storage_url, is_primary)`)
      .eq('seller_id', seller.id)
      .order('created_at', { ascending: false })
    return data || []
  },

  async uploadPhoto(file, itemId, order = 0) {
    const ext = file.name.split('.').pop()
    const path = `items/${itemId}/${Date.now()}_${order}.${ext}`
    const { error } = await sb().storage
      .from('item-photos')
      .upload(path, file, { contentType: file.type })
    if (error) throw error
    const { data: { publicUrl } } = sb().storage.from('item-photos').getPublicUrl(path)
    await sb().from('item_photos').insert({
      item_id: itemId,
      storage_url: publicUrl,
      display_order: order,
      is_primary: order === 0
    })
    return publicUrl
  }
}

// ── UI HELPERS ────────────────────────────────────────────────
const UI = {
  formatCountdown(endsAt) {
    const diff = new Date(endsAt) - Date.now()
    if (diff <= 0) return { text: 'Ended', urgent: true }
    const days = Math.floor(diff / 86400000)
    const hours = Math.floor((diff % 86400000) / 3600000)
    const mins = Math.floor((diff % 3600000) / 60000)
    const secs = Math.floor((diff % 60000) / 1000)
    const urgent = diff < 3600000
    let text = days > 0 ? `${days}d ${hours}h` : hours > 0 ? `${hours}h ${mins}m` : `${mins}m ${secs}s`
    return { text, urgent }
  },

  startCountdowns() {
    setInterval(() => {
      document.querySelectorAll('[data-ends-at]').forEach(el => {
        const { text, urgent } = UI.formatCountdown(el.dataset.endsAt)
        el.textContent = text
        el.classList.toggle('urgent', urgent)
        if (urgent) el.style.color = '#B03030'
      })
    }, 1000)
  },

  formatPrice(n) {
    return '$' + parseFloat(n || 0).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 })
  },

  primaryPhoto(photos) {
    if (!photos || photos.length === 0) return null
    return (photos.find(p => p.is_primary) || photos[0])?.storage_url
  },

  // Render a single auction card (used on homepage + browse)
  renderCard(item) {
    const photo = UI.primaryPhoto(item.item_photos)
    const bid = item.current_bid || item.starting_bid
    const premium = (bid * (item.buyers_premium_pct || 15) / 100).toFixed(0)
    const shipping = item.est_shipping_min
      ? `~$${Math.round((item.est_shipping_min + item.est_shipping_max) / 2)}`
      : 'TBD'
    const total = (parseFloat(bid) + parseFloat(premium) + (item.est_shipping_min ? (item.est_shipping_min + item.est_shipping_max) / 2 : 0)).toFixed(0)
    const seller = item.sellers

    return `
      <div class="ac-card" onclick="window.location.href='auction-item-detail.html?id=${item.id}'">
        <div class="ac-img" style="${photo ? `background:url('${photo}') center/cover no-repeat` : ''}">
          ${!photo ? '<span style="font-size:64px">🪑</span>' : ''}
          <div class="ac-badge ${item.bid_count > 20 ? 'hot' : 'live'}">${item.bid_count > 20 ? '🔥 HOT' : '🔴 LIVE'}</div>
          <button class="ac-fav" onclick="event.stopPropagation();FNA.Watchlist.toggle('${item.id}').then(w=>this.textContent=w?'❤️':'🤍')">🤍</button>
        </div>
        <div class="ac-body">
          <div class="ac-estate">${seller?.business_name || ''} · ${seller?.city || ''}, ${seller?.state || ''}</div>
          <div class="ac-name">${item.title}</div>
          <div class="ac-cond ${item.condition}">✅ ${item.condition.charAt(0).toUpperCase() + item.condition.slice(1)} Condition</div>
          <div class="ac-pricing">
            <div>
              <div class="ac-bid-lbl">Current Bid</div>
              <div class="ac-bid">${UI.formatPrice(bid)}</div>
              <div class="ac-ct">${item.bid_count} bid${item.bid_count !== 1 ? 's' : ''}</div>
            </div>
            <div style="text-align:right">
              <div class="ac-time-lbl">Ends In</div>
              <div class="ac-time" data-ends-at="${item.ends_at}">--</div>
            </div>
          </div>
          <div class="trans-panel">
            <div class="tp-hd">💡 Full Cost Estimate</div>
            <div class="tp-row"><span>Current bid</span><span>${UI.formatPrice(bid)}</span></div>
            <div class="tp-row"><span>Buyer's premium (${item.buyers_premium_pct || 15}%)</span><span>$${premium}</span></div>
            <div class="tp-row"><span>Est. shipping</span><span>${shipping}</span></div>
            <div class="tp-total"><span>Estimated total</span><span>~${UI.formatPrice(total)}</span></div>
          </div>
          <div class="ac-seller">
            ${seller?.avg_rating ? `⭐ ${seller.avg_rating} · ` : ''}${seller?.business_name || ''}
          </div>
          <div class="ac-actions">
            <button class="btn-bid-c" onclick="event.stopPropagation();window.location.href='auction-item-detail.html?id=${item.id}'">View &amp; Bid</button>
            <button class="btn-watch-c" onclick="event.stopPropagation();FNA.Watchlist.toggle('${item.id}').then(w=>this.textContent=w?'❤️ Watching':'👁 Watch')">👁 Watch</button>
          </div>
        </div>
      </div>`
  },

  toast(message, title = '') {
    const t = document.getElementById('the-toast')
    if (!t) return
    const ttl = document.getElementById('t-ttl')
    const msg = document.getElementById('t-msg')
    if (ttl) ttl.textContent = title
    if (msg) msg.textContent = message
    t.classList.add('on')
    setTimeout(() => t.classList.remove('on'), 3400)
  }
}

// ── PAGE LOADERS ──────────────────────────────────────────────

// Homepage — load live auction cards
async function loadHomepageAuctions() {
  const grid = document.getElementById('live-auctions-grid')
  if (!grid) return
  grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:40px;color:#999">Loading live auctions…</div>'

  try {
    const items = await Items.getLive({ limit: 3 })
    if (items.length === 0) {
      grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:40px;color:#999">No live auctions right now. Check back soon!</div>'
      return
    }
    grid.innerHTML = items.map(UI.renderCard).join('')
    UI.startCountdowns()
  } catch (e) {
    console.error('loadHomepageAuctions:', e)
    grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:40px;color:#999">Could not load auctions. Please refresh.</div>'
  }
}

// Browse page — load + filter items
async function loadBrowseItems(filters = {}) {
  const grid = document.getElementById('results-grid')
  const countEl = document.getElementById('results-count')
  if (!grid) return

  grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:60px;color:#999;font-size:15px">Loading auctions…</div>'

  try {
    const items = await Items.getLive({
      category: filters.category,
      search: filters.search,
      sort: filters.sort || 'ends_at',
      limit: 24
    })

    if (countEl) countEl.textContent = items.length
    // Also update the top summary count
    var topCount = document.getElementById('result-count')
    if (topCount) topCount.textContent = items.length

    if (items.length === 0) {
      grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:60px;color:#999">No items match your filters.</div>'
      return
    }

    grid.innerHTML = items.map(item => {
      const photo = UI.primaryPhoto(item.item_photos)
      const bid = item.current_bid || item.starting_bid
      const premium = (bid * (item.buyers_premium_pct || 15) / 100).toFixed(0)
      const shipping = item.est_shipping_min ? `~$${Math.round((item.est_shipping_min + item.est_shipping_max) / 2)}` : 'TBD'
      const total = (parseFloat(bid) + parseFloat(premium) + (item.est_shipping_min ? (item.est_shipping_min + item.est_shipping_max) / 2 : 0)).toFixed(0)
      return `
        <a class="a-card" href="auction-item-detail.html?id=${item.id}">
          <div class="card-img" style="${photo ? `background:url('${photo}') center/cover no-repeat;font-size:0` : ''}">
            ${!photo ? `<span style="font-size:52px">🪑</span>` : ''}
            <div class="card-badge ${item.bid_count > 20 ? 'hot' : 'live'}">${item.bid_count > 20 ? '🔥 HOT' : '🔴 LIVE'}</div>
            <button class="card-fav" onclick="event.stopPropagation();event.preventDefault();FNA.Watchlist.toggle('${item.id}')">🤍</button>
          </div>
          <div class="card-body">
            <div class="card-estate">${item.sellers?.business_name || ''} · ${item.sellers?.city || ''}</div>
            <div class="card-name">${item.title}</div>
            <div class="card-cond ${item.condition}">${item.condition.charAt(0).toUpperCase() + item.condition.slice(1)}</div>
            <div class="card-pricing">
              <div><div class="card-bid-lbl">Current Bid</div><div class="card-bid">${UI.formatPrice(bid)}</div><div class="card-bids">${item.bid_count} bids</div></div>
              <div style="text-align:right"><div class="card-bid-lbl">Ends In</div><div class="card-time" data-ends-at="${item.ends_at}">--</div></div>
            </div>
            <div class="card-transparency">
              <div class="ct-row"><span>Bid + 15% premium + shipping</span><span>~${UI.formatPrice(total)}</span></div>
            </div>
          </div>
        </a>`
    }).join('')

    UI.startCountdowns()
  } catch (e) {
    console.error('loadBrowseItems:', e)
    grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:60px;color:#f00">Error loading items: ' + e.message + '</div>'
  }
}

// Item detail page — load single item by URL param
async function loadItemDetail() {
  const id = new URLSearchParams(window.location.search).get('id')
  if (!id) return // Still show demo item if no ID

  try {
    const item = await Items.getById(id)
    if (!item) return

    // Update title
    const titleEl = document.querySelector('.item-title')
    if (titleEl) titleEl.textContent = item.title

    // Update bid amount
    const bidEl = document.querySelector('.bp-bid-amt')
    if (bidEl) bidEl.textContent = UI.formatPrice(item.current_bid || item.starting_bid)

    // Update bid count
    const bidCountEl = document.querySelector('.bp-bid-count')
    if (bidCountEl) bidCountEl.textContent = `${item.bid_count} bids`

    // Update countdown
    const countdownEl = document.querySelector('[data-ends-at]')
    if (countdownEl) countdownEl.dataset.endsAt = item.ends_at

    // Update transparency panel
    const bid = item.current_bid || item.starting_bid
    const premium = (bid * (item.buyers_premium_pct || 15) / 100)
    const tpBid = document.getElementById('tp-bid')
    const tpPremium = document.getElementById('tp-premium')
    const tpTotal = document.getElementById('tp-total')
    if (tpBid) tpBid.textContent = UI.formatPrice(bid)
    if (tpPremium) tpPremium.textContent = UI.formatPrice(premium)
    if (tpTotal) tpTotal.textContent = '~' + UI.formatPrice(bid + premium + (item.est_shipping_min || 0))

    // Update description
    const descEl = document.querySelector('.item-description')
    if (descEl) descEl.textContent = item.description

    // Update condition
    const condEl = document.querySelector('.item-condition-badge')
    if (condEl) condEl.textContent = item.condition

    // Update seller info
    const sellerEl = document.querySelector('.seller-name')
    if (sellerEl) sellerEl.textContent = item.sellers?.business_name || ''

    // Update main photo
    const mainPhoto = UI.primaryPhoto(item.item_photos)
    if (mainPhoto) {
      const mainImgEl = document.querySelector('.gallery-main-img')
      if (mainImgEl) {
        mainImgEl.style.backgroundImage = `url('${mainPhoto}')`
        mainImgEl.style.backgroundSize = 'cover'
        mainImgEl.style.backgroundPosition = 'center'
      }
    }

    // Subscribe to live bid updates
    Items.subscribeToItem(id, (updated) => {
      if (bidEl) bidEl.textContent = UI.formatPrice(updated.current_bid)
      if (bidCountEl) bidCountEl.textContent = `${updated.bid_count} bids`
      if (tpBid) tpBid.textContent = UI.formatPrice(updated.current_bid)
      UI.toast(`New bid: ${UI.formatPrice(updated.current_bid)}`, '⚡ Live Update')
    })

    UI.startCountdowns()
  } catch (e) {
    console.error('loadItemDetail:', e)
  }
}

// ── AUTO-RUN ON PAGE LOAD ─────────────────────────────────────
document.addEventListener('DOMContentLoaded', async () => {
  try {
    // Detect which page we're on and load accordingly
    const path = window.location.pathname

    if (path.includes('family-nest-auctions') || path === '/' || path.endsWith('index.html')) {
      await loadHomepageAuctions()
    }

    if (path.includes('auction-browse')) {
      const q = new URLSearchParams(window.location.search).get('q')
      await loadBrowseItems({ search: q || '' })
    }

    if (path.includes('auction-item-detail')) {
      await loadItemDetail()
    }

    // Auto-open login/register modal from URL params
    const params = new URLSearchParams(window.location.search)
    if (params.get('login') && typeof openOv === 'function') openOv('login')
    if (params.get('register') && typeof openOv === 'function') openOv('register')

    UI.startCountdowns()

  } catch (e) {
    console.error('FNA init error:', e)
  }
})

// ── GLOBAL EXPORT ─────────────────────────────────────────────
window.FNA = { Auth, Items, Bidding, Watchlist, Seller, UI, loadBrowseItems }

/**
 * Family Nest Auctions — Frontend API Client
 * Supabase project: hwsjgclteuezauveujit
 */

const SUPABASE_URL = 'https://hwsjgclteuezauveujit.supabase.co'
const SUPABASE_ANON_KEY = 'sb_publishable_3-tTloiwTqSEZCw4_m288w_FoR7OgxS'
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
        seller_id, period, condition_notes, reserve_price,
        dimensions_w, dimensions_h, dimensions_d, weight_lbs,
        origin_city, origin_state, origin_country,
        provenance, authenticity_notes, restoration_history,
        materials, era, style, color, markings,
        packaging_notes, shipping_notes, local_pickup_ok,
        created_at, updated_at,
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
        sellers (id, business_name, avg_rating, total_reviews, total_sales, city, state)
      `)
      .eq('id', id)
      .single()
    if (error) { console.error('getById error:', error); return null }
    // Increment view count (best-effort)
    sb().rpc('increment_view_count', { p_item_id: id }).catch(() => {})
    return data
  },

  async getBidHistory(itemId) {
    const { data, error } = await sb()
      .from('bids')
      .select('amount, created_at, is_winning')
      .eq('item_id', itemId)
      .order('amount', { ascending: false })
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
        items (id, title, current_bid, ends_at, status,
          item_photos (storage_url, is_primary))
      `)
      .eq('user_id', user.id)
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
  },

  async getDashboardStats() {
    const user = await Auth.getUser()
    if (!user) return null
    const { data: seller } = await sb()
      .from('sellers')
      .select('id')
      .eq('user_id', user.id)
      .single()
    if (!seller) return null

    // Get stats for the current month
    const now = new Date()
    const startOfMonth = new Date(now.getFullYear(), now.getMonth(), 1).toISOString()
    const endOfMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).toISOString()

    const { data: stats } = await sb()
      .from('items')
      .select(`
        status,
        current_bid,
        starting_bid,
        bid_count,
        view_count,
        created_at
      `)
      .eq('seller_id', seller.id)
      .gte('created_at', startOfMonth)
      .lte('created_at', endOfMonth)

    if (!stats) return null

    const liveItems = stats.filter(item => item.status === 'live')
    const soldItems = stats.filter(item => item.status === 'sold')
    const draftItems = stats.filter(item => item.status === 'draft')
    
    const revenue = soldItems.reduce((sum, item) => sum + (item.current_bid || 0), 0)
    const totalBids = stats.reduce((sum, item) => sum + (item.bid_count || 0), 0)
    const totalViews = stats.reduce((sum, item) => sum + (item.view_count || 0), 0)
    const avgRating = 4.9 // This would come from reviews table

    return {
      revenue,
      liveCount: liveItems.length,
      totalBids,
      totalViews,
      avgRating,
      soldCount: soldItems.length,
      draftCount: draftItems.length,
      awaitingShipment: 5 // This would come from orders table
    }
  },

  async getMySales() {
    const user = await Auth.getUser()
    if (!user) return []
    const { data: seller } = await sb()
      .from('sellers')
      .select('id')
      .eq('user_id', user.id)
      .single()
    if (!seller) return []

    const { data } = await sb()
      .from('estate_sales')
      .select('*')
      .eq('seller_id', seller.id)
      .order('starts_at', { ascending: false })

    return data || []
  },

  async getShippingItems() {
    const user = await Auth.getUser()
    if (!user) return []
    const { data: seller } = await sb()
      .from('sellers')
      .select('id')
      .eq('user_id', user.id)
      .single()
    if (!seller) return []

    // Get items that are sold but not yet shipped
    const { data } = await sb()
      .from('items')
      .select(`
        *,
        item_photos (storage_url, is_primary),
        bids!inner (user_id, amount, is_winning)
      `)
      .eq('seller_id', seller.id)
      .eq('status', 'sold')
      .eq('bids.is_winning', true)
      .order('ends_at', { ascending: true })

    return data || []
  },

  async getPayouts() {
    const user = await Auth.getUser()
    if (!user) return []
    const { data: seller } = await sb()
      .from('sellers')
      .select('id')
      .eq('user_id', user.id)
      .single()
    if (!seller) return []

    const { data } = await sb()
      .from('payouts')
      .select('*')
      .eq('seller_id', seller.id)
      .order('created_at', { ascending: false })

    return data || []
  },

  async getReviews() {
    const user = await Auth.getUser()
    if (!user) return []
    const { data: seller } = await sb()
      .from('sellers')
      .select('id')
      .eq('user_id', user.id)
      .single()
    if (!seller) return []

    const { data } = await sb()
      .from('reviews')
      .select(`
        *,
        users (full_name),
        items (title)
      `)
      .eq('seller_id', seller.id)
      .order('created_at', { ascending: false })
      .limit(20)

    return data || []
  }
}

// ── ADMIN ─────────────────────────────────────────────────────
const Admin = {
  async getPlatformStats() {
    // Get counts
    const [liveItems, users, estateSales, todayBids, disputes] = await Promise.all([
      sb().from('items').select('*', { count: 'exact', head: true }).eq('status', 'live'),
      sb().from('profiles').select('*', { count: 'exact', head: true }),
      sb().from('estate_sales').select('*', { count: 'exact', head: true }).in('status', ['live', 'upcoming']),
      sb().from('bids').select('*', { count: 'exact', head: true }).gte('created_at', new Date().toISOString().slice(0, 10)),
      sb().from('disputes').select('*', { count: 'exact', head: true }).eq('status', 'open')
    ])

    // Get GMV for current month
    const startOfMonth = new Date(new Date().getFullYear(), new Date().getMonth(), 1).toISOString()
    const endOfMonth = new Date(new Date().getFullYear(), new Date().getMonth() + 1, 0).toISOString()
    
    const { data: items } = await sb()
      .from('items')
      .select('current_bid, status')
      .eq('status', 'sold')
      .gte('ends_at', startOfMonth)
      .lte('ends_at', endOfMonth)

    const gmv = items?.reduce((sum, item) => sum + (item.current_bid || 0), 0) || 0
    const platformRevenue = gmv * 0.15 // 15% platform fee

    return {
      gmv,
      platformRevenue,
      liveListings: liveItems.count || 0,
      registeredBuyers: users.count || 0,
      activeEstateSales: estateSales.count || 0,
      bidsToday: todayBids.count || 0,
      openDisputes: disputes.count || 0,
      avgRating: 4.87
    }
  },

  async getAllListings({ status, category, seller, search, limit = 50, offset = 0 } = {}) {
    let query = sb()
      .from('items')
      .select(`
        id, title, description, category, condition,
        current_bid, starting_bid, bid_count, view_count,
        ends_at, starts_at, status, item_number,
        seller_id,
        item_photos (storage_url, is_primary),
        sellers (id, business_name, city, state)
      `)
      .order('created_at', { ascending: false })
      .range(offset, offset + limit - 1)

    if (status && status !== 'All') query = query.eq('status', status)
    if (category && category !== 'All') query = query.eq('category', category)
    if (seller && seller !== 'All') query = query.eq('seller_id', seller)
    if (search) query = query.or(`title.ilike.%${search}%,description.ilike.%${search}%`)

    const { data, error, count } = await query
    if (error) { console.error('getAllListings error:', error); return { items: [], total: 0 } }
    return { items: data || [], total: count || 0 }
  },

  async getAllUsers({ status, role, search, limit = 50, offset = 0 } = {}) {
    let
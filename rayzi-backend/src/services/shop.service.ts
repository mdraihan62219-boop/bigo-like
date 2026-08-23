import { supabase } from '../config/database'

export class ShopService {
  static async listItems(category?: string) {
    let query = supabase.from('shop_items').select('*').eq('is_active', true).order('sort_order')
    if (category) query = query.eq('category', category)
    const { data, error } = await query
    if (error) throw new Error(error.message)
    return data
  }

  static async purchase(userId: string, itemId: string) {
    if (typeof itemId !== 'string' || !itemId) throw new Error('item_id is required')
    // Price is resolved inside the DB RPC — never trust a client-sent amount.
    const { data, error } = await supabase.rpc('purchase_shop_item', { p_item_id: itemId })
    if (error) return { ok: false as const, message: error.message }
    return { ok: true as const, data }
  }

  static async inventory(userId: string) {
    const { data, error } = await supabase
      .from('user_inventory')
      .select('*, shop_items(*)')
      .eq('user_id', userId)
      .order('purchased_at', { ascending: false })
    if (error) throw new Error(error.message)
    return data
  }

  static async equip(userId: string, inventoryId: string, equip: boolean) {
    const { data: owned } = await supabase
      .from('user_inventory').select('id').eq('id', inventoryId).eq('user_id', userId).single()
    if (!owned) return { ok: false as const, status: 404, message: 'Inventory item not found' }
    const { data, error } = await supabase.rpc('equip_inventory_item', {
      p_inventory_id: inventoryId, p_equip: equip,
    })
    if (error) return { ok: false as const, status: 400, message: error.message }
    return { ok: true as const, data }
  }

  static async adminCreateItem(fields: Record<string, unknown>) {
    const allowed = ['category','tier','name','description','preview_url','price_diamonds','duration_days','effect_config','is_active','sort_order'] as const
    const row: Record<string, unknown> = {}
    for (const k of allowed) if (fields[k] !== undefined) row[k] = fields[k]
    if (!row.name || !row.category) throw new Error('name and category are required')
    const { data, error } = await supabase.from('shop_items').insert(row).select().single()
    if (error) throw new Error(error.message)
    return data
  }

  static async adminUpdateItem(id: string, fields: Record<string, unknown>) {
    const allowed = ['tier','name','description','preview_url','price_diamonds','duration_days','effect_config','is_active','sort_order'] as const
    const patch: Record<string, unknown> = {}
    for (const k of allowed) if (fields[k] !== undefined) patch[k] = fields[k]
    if (Object.keys(patch).length === 0) throw new Error('No updatable fields provided')
    const { data, error } = await supabase.from('shop_items').update(patch).eq('id', id).select().single()
    if (error) throw new Error(error.message)
    return data
  }

  static async adminDeleteItem(id: string) {
    const { error } = await supabase.from('shop_items').delete().eq('id', id)
    if (error) throw new Error(error.message)
  }

  static async adminListItems() {
    const { data, error } = await supabase.from('shop_items').select('*').order('sort_order')
    if (error) throw new Error(error.message)
    return data
  }
}

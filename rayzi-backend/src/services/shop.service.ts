import { supabase } from '../config/database'

const CATEGORY_COLUMN: Record<string, string> = {
  avatar_frame: 'equipped_frame_id',
  badge: 'equipped_badge_id',
  theme: 'equipped_theme_id',
  entry_animation: 'equipped_entry_animation_id',
}

export class ShopService {
  static async listItems(category?: string) {
    let query = supabase.from('shop_items').select('*').eq('is_active', true).order('sort_order')
    if (category) query = query.eq('category', category)
    const { data, error } = await query
    if (error) throw new Error(error.message)
    return data
  }

  /**
   * Purchase via server-side orchestration (price looked up here, deduction
   * through the existing wallet RPC, compensating refund on failure — same
   * pattern as GiftService). Explicit user id keeps this service-role safe.
   */
  static async purchase(userId: string, itemId: string) {
    if (typeof itemId !== 'string' || !itemId) throw new Error('item_id is required')

    const { data: item } = await supabase
      .from('shop_items').select('*').eq('id', itemId).eq('is_active', true).single()
    if (!item) return { ok: false as const, status: 404, message: 'Item not found' }

    // Wallet RPC rejects with 'Insufficient diamonds' when balance is short.
    const { error: deductError } = await supabase.rpc('deduct_diamonds', {
      p_user_id: userId, p_amount: item.price_diamonds,
      p_reason: 'shop_purchase', p_actor_type: 'user',
      p_actor_id: userId, p_reference_id: itemId, p_note: item.name,
    })
    if (deductError) return { ok: false as const, status: 400, message: deductError.message }

    try {
      const now = Date.now()
      const { data: existing } = await supabase
        .from('user_inventory')
        .select('id, expires_at')
        .eq('user_id', userId).eq('item_id', itemId).maybeSingle()

      let expiresAt: string | null = null
      if (item.duration_days == null) {
        expiresAt = null // permanent
      } else {
        const base = existing?.expires_at ? new Date(existing.expires_at).getTime() : now
        expiresAt = new Date(base + item.duration_days * 86_400_000).toISOString()
      }

      const { data: inv, error: invErr } = await supabase
        .from('user_inventory')
        .upsert({
          ...(existing?.id ? { id: existing.id } : {}),
          user_id: userId, item_id: itemId,
          expires_at: expiresAt,
        }, { onConflict: 'user_id,item_id' })
        .select().single()
      if (invErr) throw new Error(invErr.message)

      return {
        ok: true as const,
        data: { inventory_id: inv.id, expires_at: inv.expires_at, diamonds_spent: item.price_diamonds },
      }
    } catch (err: any) {
      // Compensating refund — never lose diamonds to a failed write. Audited.
      await supabase.rpc('add_diamonds', {
        p_user_id: userId, p_amount: item.price_diamonds,
        p_reason: 'other', p_actor_type: 'system',
        p_actor_id: null, p_reference_id: itemId,
        p_note: `refund: failed purchase of ${item.name}`,
      })
      return { ok: false as const, status: 500, message: err.message }
    }
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

  /** Equip/unequip with ownership verification; unequips previous of same category. */
  static async equip(userId: string, inventoryId: string, equip: boolean) {
    const { data: owned } = await supabase
      .from('user_inventory').select('id').eq('id', inventoryId).eq('user_id', userId).maybeSingle()
    if (!owned) return { ok: false as const, status: 404, message: 'Inventory item not found' }

    const { data: rows } = await supabase
      .from('user_inventory')
      .select('id, is_equipped, item_id, shop_items!user_inventory_item_id_fkey(category, effect_config)')
      .eq('id', inventoryId).limit(1)
    const row = rows?.[0] as any
    if (!row) return { ok: false as const, status: 404, message: 'Inventory item not found' }
    const category = row.shop_items?.category as string | undefined

    if (!equip) {
      const column = category ? CATEGORY_COLUMN[category] : undefined
      if (column) {
        await supabase.from('profiles').update({ [column]: null }).eq('id', userId)
      }
      if (category === 'name_effect') {
        await supabase.from('profiles').update({ name_effect: null }).eq('id', userId)
      }
      await supabase.from('user_inventory').update({ is_equipped: false }).eq('id', inventoryId)
      return { ok: true as const, data: { inventory_id: inventoryId, equipped: false } }
    }

    // Unequip everything else of the same category first.
    if (category) {
      const { data: catItems } = await supabase
        .from('shop_items').select('id').eq('category', category)
      const ids = (catItems ?? []).map((i: { id: string }) => i.id)
      if (ids.length > 0) {
        await supabase.from('user_inventory')
          .update({ is_equipped: false })
          .eq('user_id', userId).in('item_id', ids).neq('id', inventoryId)
      }
      const column = CATEGORY_COLUMN[category]
      if (column) {
        await supabase.from('profiles').update({ [column]: row.item_id }).eq('id', userId)
      }
      if (category === 'name_effect') {
        await supabase.from('profiles')
          .update({ name_effect: row.shop_items?.effect_config ?? null })
          .eq('id', userId)
      }
    }

    await supabase.from('user_inventory').update({ is_equipped: true }).eq('id', inventoryId)
    return { ok: true as const, data: { inventory_id: inventoryId, equipped: true } }
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

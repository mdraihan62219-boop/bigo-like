#!/usr/bin/env node
// Seeds initial shop items (King/Crown/VVIP/VIP tiers, frames, themes,
// entry animations, name effects) into Supabase.
// PREREQUISITE: run supabase/migrations/005_feature_expansion.sql first.
import 'dotenv/config'
import { createClient } from '@supabase/supabase-js'

const url = process.env.SUPABASE_URL
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY
if (!url || !serviceKey) {
  console.error('Missing SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY in rayzi-backend/.env')
  process.exit(1)
}
const supabase = createClient(url, serviceKey, { auth: { persistSession: false } })

const items = [
  // Badges (profile badges shown next to names)
  { category: 'badge', tier: 'king', name: 'KING Badge', description: 'Golden king crown badge', price_diamonds: 100000, sort_order: 10 },
  { category: 'badge', tier: 'crown', name: 'CROWN Badge', description: 'Silver crown badge', price_diamonds: 50000, sort_order: 11 },
  { category: 'badge', tier: 'vvip', name: 'VVIP Badge', description: 'Exclusive VVIP badge', price_diamonds: 25000, sort_order: 12 },
  { category: 'badge', tier: 'vip', name: 'VIP Badge', description: 'Classic VIP badge', price_diamonds: 10000, sort_order: 13 },
  // Avatar frames
  { category: 'avatar_frame', tier: 'king', name: 'Royal Flame Frame', description: 'Animated royal flame avatar frame', price_diamonds: 80000, duration_days: 30, sort_order: 20 },
  { category: 'avatar_frame', tier: 'crown', name: 'Silver Crown Frame', description: 'Silver crown avatar frame', price_diamonds: 40000, duration_days: 30, sort_order: 21 },
  { category: 'avatar_frame', tier: null, name: 'Neon Pulse Frame', description: 'Neon glow avatar frame', price_diamonds: 15000, duration_days: 30, sort_order: 22 },
  { category: 'avatar_frame', tier: null, name: 'Simple Gold Ring', description: 'Permanent gold ring frame', price_diamonds: 20000, duration_days: null, sort_order: 23 },
  // VIP tiers
  { category: 'vip_tier', tier: 'vip', name: 'VIP Membership', description: 'VIP badge + exclusive gifts (30 days)', price_diamonds: 30000, duration_days: 30, sort_order: 30 },
  { category: 'vip_tier', tier: 'vvip', name: 'VVIP Membership', description: 'VVIP badge, frame + premium features (30 days)', price_diamonds: 90000, duration_days: 30, sort_order: 31 },
  // Themes
  { category: 'theme', tier: null, name: 'Midnight Theme', description: 'Deep blue app-wide theme', price_diamonds: 12000, effect_config: { primary: '#1E3A8A', background: '#0B1120' }, duration_days: null, sort_order: 40 },
  { category: 'theme', tier: null, name: 'Rose Gold Theme', description: 'Elegant rose gold accents', price_diamonds: 18000, effect_config: { primary: '#B76E79', background: '#140D0F' }, duration_days: 30, sort_order: 41 },
  // Entry animations
  { category: 'entry_animation', tier: null, name: 'Firework Entry', description: 'Fireworks burst when you join a room', price_diamonds: 9000, duration_days: 30, sort_order: 50 },
  { category: 'entry_animation', tier: 'vvip', name: 'Dragon Descent Entry', description: 'Legendary dragon fly-in animation', price_diamonds: 60000, duration_days: 30, sort_order: 51 },
  // Name effects
  { category: 'name_effect', tier: null, name: 'Golden Name', description: 'Gradient gold username', price_diamonds: 15000, duration_days: 30, effect_config: { prefix_emojis: [], suffix_emojis: [], gradient_colors: ['#f5c518', '#ffffff'] }, sort_order: 60 },
  { category: 'name_effect', tier: null, name: 'Crowned Name', description: '👑 prefix with rose gradient', price_diamonds: 22000, duration_days: 30, effect_config: { prefix_emojis: ['👑'], suffix_emojis: [], gradient_colors: ['#ff6b9d', '#ffffff'] }, sort_order: 61 },
]

async function main() {
  // Manual upsert keyed on (category, name) — no unique constraint required.
  let inserted = 0
  let updated = 0
  for (const item of items) {
    const { data: existing } = await supabase
      .from('shop_items')
      .select('id')
      .eq('category', item.category)
      .eq('name', item.name)
      .maybeSingle()

    if (existing?.id) {
      const { error } = await supabase.from('shop_items').update(item).eq('id', existing.id)
      if (error) throw new Error(`Update failed for ${item.name}: ${error.message}`)
      updated++
    } else {
      const { error } = await supabase.from('shop_items').insert(item)
      if (error) throw new Error(`Insert failed for ${item.name}: ${error.message}`)
      inserted++
    }
    console.log(`${existing?.id ? 'updated' : 'created'}: ${item.name}`)
  }

  const { count } = await supabase.from('shop_items').select('*', { count: 'exact', head: true })
  console.log(`Shop seeded — ${inserted} created, ${updated} updated, ${count} total items.`)
}

main().catch((e) => {
  console.error(e.message)
  process.exit(1)
})

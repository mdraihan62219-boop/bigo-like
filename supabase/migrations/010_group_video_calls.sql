-- 010_group_video_calls.sql
-- Group Video Call system: multi-seat video rooms with host controls,
-- gift events, and official host badges.

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. group_call_rooms — video-enabled group call rooms
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS group_call_rooms (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  host_id       UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title         TEXT NOT NULL DEFAULT 'Group Call',
  description   TEXT DEFAULT '',
  category      TEXT NOT NULL DEFAULT 'general',
  max_seats     INTEGER NOT NULL DEFAULT 9,
  status        TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','ended')),
  channel_name  TEXT UNIQUE NOT NULL,
  is_private    BOOLEAN NOT NULL DEFAULT FALSE,
  password      TEXT,
  current_viewers INTEGER NOT NULL DEFAULT 0,
  total_gifts   INTEGER NOT NULL DEFAULT 0,
  started_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at      TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE group_call_rooms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "group_call_rooms_select" ON group_call_rooms
  FOR SELECT USING (status = 'active' OR auth.uid() = host_id);

CREATE POLICY "group_call_rooms_insert" ON group_call_rooms
  FOR INSERT WITH CHECK (auth.uid() = host_id);

CREATE POLICY "group_call_rooms_update" ON group_call_rooms
  FOR UPDATE USING (auth.uid() = host_id);

-- ---------------------------------------------------------------------------
-- 2. group_call_seats — seat assignments (who is on camera)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS group_call_seats (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  room_id     UUID NOT NULL REFERENCES group_call_rooms(id) ON DELETE CASCADE,
  user_id     UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  seat_index  INTEGER NOT NULL CHECK (seat_index >= 0 AND seat_index < 12),
  role        TEXT NOT NULL DEFAULT 'co_host' CHECK (role IN ('host','co_host','guest')),
  is_muted    BOOLEAN NOT NULL DEFAULT FALSE,
  video_enabled BOOLEAN NOT NULL DEFAULT TRUE,
  joined_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(room_id, seat_index),
  UNIQUE(room_id, user_id)
);

ALTER TABLE group_call_seats ENABLE ROW LEVEL SECURITY;

CREATE POLICY "group_call_seats_select" ON group_call_seats
  FOR SELECT USING (true);

CREATE POLICY "group_call_seats_insert" ON group_call_seats
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM group_call_rooms r
      WHERE r.id = room_id AND (
        r.host_id = auth.uid()
        OR EXISTS (
          SELECT 1 FROM group_call_seats s
          WHERE s.room_id = r.id AND s.user_id = auth.uid()
          AND s.role IN ('host','co_host')
        )
      )
    )
  );

CREATE POLICY "group_call_seats_delete" ON group_call_seats
  FOR DELETE USING (
    auth.uid() = user_id
    OR EXISTS (
      SELECT 1 FROM group_call_rooms r
      WHERE r.id = room_id AND r.host_id = auth.uid()
    )
  );

-- ---------------------------------------------------------------------------
-- 3. group_gift_events — gift events in group calls
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS group_gift_events (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  room_id     UUID NOT NULL REFERENCES group_call_rooms(id) ON DELETE CASCADE,
  sender_id   UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  gift_id     UUID NOT NULL REFERENCES gifts(id),
  receiver_id UUID REFERENCES profiles(id),
  seat_index  INTEGER,
  amount      INTEGER NOT NULL DEFAULT 1,
  coins_spent INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE group_gift_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "group_gift_events_select" ON group_gift_events
  FOR SELECT USING (true);

CREATE POLICY "group_gift_events_insert" ON group_gift_events
  FOR INSERT WITH CHECK (auth.uid() = sender_id);

-- ---------------------------------------------------------------------------
-- 4. RPC: Create a group call room
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS create_group_call_room;
CREATE OR REPLACE FUNCTION create_group_call_room(
  p_title TEXT DEFAULT 'Group Call',
  p_description TEXT DEFAULT '',
  p_category TEXT DEFAULT 'general',
  p_max_seats INTEGER DEFAULT 9,
  p_is_private BOOLEAN DEFAULT FALSE,
  p_password TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_room_id UUID;
  v_channel TEXT;
  v_host_id UUID;
  v_result JSONB;
BEGIN
  v_host_id := auth.uid();
  IF v_host_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  v_channel := 'gc_' || v_host_id || '_' || extract(epoch from now())::bigint;

  INSERT INTO group_call_rooms (host_id, title, description, category, max_seats, channel_name, is_private, password)
  VALUES (v_host_id, p_title, p_description, p_category, p_max_seats, v_channel, p_is_private, p_password)
  RETURNING id INTO v_room_id;

  INSERT INTO group_call_seats (room_id, user_id, seat_index, role)
  VALUES (v_room_id, v_host_id, 0, 'host');

  SELECT jsonb_build_object(
    'id', r.id,
    'host_id', r.host_id,
    'title', r.title,
    'description', r.description,
    'category', r.category,
    'max_seats', r.max_seats,
    'channel_name', r.channel_name,
    'is_private', r.is_private,
    'status', r.status,
    'created_at', r.created_at,
    'seats', (
      SELECT jsonb_agg(jsonb_build_object(
        'seat_index', s.seat_index,
        'user_id', s.user_id,
        'role', s.role,
        'is_muted', s.is_muted,
        'video_enabled', s.video_enabled,
        'display_name', p.display_name,
        'avatar_url', p.avatar_url,
        'username', p.username,
        'is_verified', p.is_verified
      ))
      FROM group_call_seats s
      JOIN profiles p ON p.id = s.user_id
      WHERE s.room_id = r.id
    )
  ) INTO v_result
  FROM group_call_rooms r
  WHERE r.id = v_room_id;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION create_group_call_room TO service_role;

-- ---------------------------------------------------------------------------
-- 5. RPC: Join a group call seat
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS join_group_call_seat;
CREATE OR REPLACE FUNCTION join_group_call_seat(
  p_room_id UUID,
  p_seat_index INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_room_status TEXT;
  v_existing_count INTEGER;
  v_max_seats INTEGER;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT status, max_seats INTO v_room_status, v_max_seats
  FROM group_call_rooms WHERE id = p_room_id;

  IF v_room_status IS NULL THEN
    RAISE EXCEPTION 'Room not found';
  END IF;
  IF v_room_status != 'active' THEN
    RAISE EXCEPTION 'Room is not active';
  END IF;

  IF EXISTS (
    SELECT 1 FROM group_call_seats
    WHERE room_id = p_room_id AND user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'Already in this room';
  END IF;

  IF EXISTS (
    SELECT 1 FROM group_call_seats
    WHERE room_id = p_room_id AND seat_index = p_seat_index
  ) THEN
    RAISE EXCEPTION 'Seat is occupied';
  END IF;

  SELECT count(*) INTO v_existing_count
  FROM group_call_seats WHERE room_id = p_room_id;

  IF v_existing_count >= v_max_seats THEN
    RAISE EXCEPTION 'Room is full';
  END IF;

  INSERT INTO group_call_seats (room_id, user_id, seat_index, role)
  VALUES (p_room_id, v_user_id, p_seat_index, 'co_host');

  UPDATE group_call_rooms SET current_viewers = current_viewers + 1 WHERE id = p_room_id;

  RETURN jsonb_build_object(
    'seat_index', p_seat_index,
    'role', 'co_host',
    'joined_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION join_group_call_seat TO service_role;

-- ---------------------------------------------------------------------------
-- 6. RPC: Leave a group call seat
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS leave_group_call_seat;
CREATE OR REPLACE FUNCTION leave_group_call_seat(p_room_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID;
  v_is_host BOOLEAN;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT (host_id = v_user_id) INTO v_is_host
  FROM group_call_rooms WHERE id = p_room_id;

  DELETE FROM group_call_seats
  WHERE room_id = p_room_id AND user_id = v_user_id;

  UPDATE group_call_rooms SET current_viewers = greatest(0, current_viewers - 1) WHERE id = p_room_id;

  IF v_is_host THEN
    UPDATE group_call_rooms SET status = 'ended', ended_at = now() WHERE id = p_room_id;
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION leave_group_call_seat TO service_role;

-- ---------------------------------------------------------------------------
-- 7. RPC: Kick a user from a group call seat
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS kick_group_call_seat;
CREATE OR REPLACE FUNCTION kick_group_call_seat(
  p_room_id UUID,
  p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM group_call_rooms
    WHERE id = p_room_id AND host_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'Only the host can kick users';
  END IF;

  DELETE FROM group_call_seats
  WHERE room_id = p_room_id AND user_id = p_user_id AND seat_index != 0;

  UPDATE group_call_rooms SET current_viewers = greatest(0, current_viewers - 1) WHERE id = p_room_id;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION kick_group_call_seat TO service_role;

-- ---------------------------------------------------------------------------
-- 8. RPC: Swap host (transfer host seat)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS swap_group_call_host;
CREATE OR REPLACE FUNCTION swap_group_call_host(
  p_room_id UUID,
  p_new_host_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_old_host_id UUID;
  v_old_host_seat INTEGER;
  v_new_host_seat INTEGER;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT host_id INTO v_old_host_id FROM group_call_rooms WHERE id = p_room_id;

  IF v_old_host_id != v_caller_id THEN
    RAISE EXCEPTION 'Only the current host can transfer host role';
  END IF;

  SELECT seat_index INTO v_old_host_seat
  FROM group_call_seats WHERE room_id = p_room_id AND user_id = v_old_host_id;

  SELECT seat_index INTO v_new_host_seat
  FROM group_call_seats WHERE room_id = p_room_id AND user_id = p_new_host_id;

  IF v_new_host_seat IS NULL THEN
    RAISE EXCEPTION 'New host must be in a seat';
  END IF;

  UPDATE group_call_seats SET role = 'co_host'
  WHERE room_id = p_room_id AND user_id = v_old_host_id;

  UPDATE group_call_seats SET role = 'host'
  WHERE room_id = p_room_id AND user_id = p_new_host_id;

  UPDATE group_call_rooms SET host_id = p_new_host_id WHERE id = p_room_id;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION swap_group_call_host TO service_role;

-- ---------------------------------------------------------------------------
-- 9. RPC: Toggle mute/video for a seat
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS toggle_group_call_seat;
CREATE OR REPLACE FUNCTION toggle_group_call_seat(
  p_room_id UUID,
  p_user_id UUID,
  p_field TEXT,
  p_value BOOLEAN
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF v_caller_id != p_user_id THEN
    IF NOT EXISTS (
      SELECT 1 FROM group_call_rooms
      WHERE id = p_room_id AND host_id = v_caller_id
    ) THEN
      RAISE EXCEPTION 'Only host can modify other users seats';
    END IF;
  END IF;

  IF p_field = 'is_muted' THEN
    UPDATE group_call_seats SET is_muted = p_value
    WHERE room_id = p_room_id AND user_id = p_user_id;
  ELSIF p_field = 'video_enabled' THEN
    UPDATE group_call_seats SET video_enabled = p_value
    WHERE room_id = p_room_id AND user_id = p_user_id;
  ELSE
    RAISE EXCEPTION 'Invalid field: %', p_field;
  END IF;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION toggle_group_call_seat TO service_role;

-- ---------------------------------------------------------------------------
-- 10. RPC: Grant co-host role
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS grant_group_call_co_host;
CREATE OR REPLACE FUNCTION grant_group_call_co_host(
  p_room_id UUID,
  p_user_id UUID,
  p_grant BOOLEAN DEFAULT TRUE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
  v_new_role TEXT;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM group_call_rooms
    WHERE id = p_room_id AND host_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'Only the host can grant/revoke co-host';
  END IF;

  v_new_role := CASE WHEN p_grant THEN 'co_host' ELSE 'guest' END;

  UPDATE group_call_seats SET role = v_new_role
  WHERE room_id = p_room_id AND user_id = p_user_id AND seat_index != 0;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION grant_group_call_co_host TO service_role;

-- ---------------------------------------------------------------------------
-- 11. RPC: End group call (host only)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS end_group_call;
CREATE OR REPLACE FUNCTION end_group_call(p_room_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_caller_id UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM group_call_rooms
    WHERE id = p_room_id AND host_id = v_caller_id
  ) THEN
    RAISE EXCEPTION 'Only the host can end the call';
  END IF;

  UPDATE group_call_rooms SET status = 'ended', ended_at = now() WHERE id = p_room_id;
  DELETE FROM group_call_seats WHERE room_id = p_room_id;

  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION end_group_call TO service_role;

-- ---------------------------------------------------------------------------
-- 12. RPC: Set Official Host badge (admin only)
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS set_official_host;
CREATE OR REPLACE FUNCTION set_official_host(
  p_user_id UUID,
  p_official BOOLEAN DEFAULT TRUE
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE profiles SET is_verified = p_official WHERE id = p_user_id;
  RETURN true;
END;
$$;

GRANT EXECUTE ON FUNCTION set_official_host TO service_role;

-- ---------------------------------------------------------------------------
-- 13. Indexes for performance
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_group_call_rooms_status ON group_call_rooms(status);
CREATE INDEX IF NOT EXISTS idx_group_call_rooms_host ON group_call_rooms(host_id);
CREATE INDEX IF NOT EXISTS idx_group_call_rooms_channel ON group_call_rooms(channel_name);
CREATE INDEX IF NOT EXISTS idx_group_call_seats_room ON group_call_seats(room_id);
CREATE INDEX IF NOT EXISTS idx_group_call_seats_user ON group_call_seats(user_id);
CREATE INDEX IF NOT EXISTS idx_group_gift_events_room ON group_gift_events(room_id);
CREATE INDEX IF NOT EXISTS idx_group_gift_events_sender ON group_gift_events(sender_id);

COMMIT;

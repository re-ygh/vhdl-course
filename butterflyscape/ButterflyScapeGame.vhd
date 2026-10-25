library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ButterflyScapeGame is
  port(
    CLK_24MHz : in  std_logic;
    RESET     : in  std_logic;
    FrameTick : in  std_logic;

    Key       : in  std_logic_vector(3 downto 0);

    ScanlineX : in  std_logic_vector(10 downto 0);
    ScanlineY : in  std_logic_vector(10 downto 0);

    ColorOut  : out std_logic_vector(5 downto 0);

    ScoreOut  : out std_logic_vector(7 downto 0);
    WinOut    : out std_logic;
    LoseOut   : out std_logic;

    DebugLeds : out std_logic_vector(7 downto 0)
  );
end;

architecture rtl of ButterflyScapeGame is

  -- ============================================================================
  -- 1) Types (ISE-friendly)
  -- ============================================================================
  subtype u2  is unsigned(1 downto 0);
  subtype u3  is unsigned(2 downto 0);
  subtype u4  is unsigned(3 downto 0);
  subtype u5  is unsigned(4 downto 0);
  subtype u7  is unsigned(6 downto 0);
  subtype u8  is unsigned(7 downto 0);
  subtype u9  is unsigned(8 downto 0);
  subtype u10 is unsigned(9 downto 0);
  subtype u11 is unsigned(10 downto 0);

  subtype s11 is signed(10 downto 0);
  subtype s12 is signed(11 downto 0);

  -- ============================================================================
  -- 2) VGA and Game Window
  -- ============================================================================
  constant VGA_W : integer := 640;
  constant VGA_H : integer := 480;

  constant SCREEN_W : integer := 384;
  constant SCREEN_H : integer := 360;

  constant OFFX : integer := (VGA_W - SCREEN_W)/2;
  constant OFFY : integer := (VGA_H - SCREEN_H)/2;

  constant Q6_SCALE        : integer := 64;
  constant SCREEN_MAX_X_Q6 : integer := (SCREEN_W-1) * Q6_SCALE;
  constant SCREEN_MAX_Y_Q6 : integer := (SCREEN_H-1) * Q6_SCALE;

  -- ============================================================================
  -- 3) Gameplay tuning
  -- ============================================================================
  constant LOSE_LIMIT : integer := 255;
  constant MAX_STORE  : integer := 13;

  -- ============================================================================
  -- Storage index width
  --   NOTE: Several state-machine indices and chain_len were previously 4-bit.
  --   When MAX_STORE > 15 this causes overflow (e.g. chain resets after 15).
  --   Make the width automatically match MAX_STORE to avoid truncation.
  -- ============================================================================
  function clog2(n : natural) return natural is
    variable r : natural := 0;
    variable v : natural := 1;
  begin
    while v < n loop
      v := v * 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  constant IDX_W : natural := clog2(MAX_STORE + 1); -- +1 because chain_len can be MAX_STORE
  subtype idx_t  is unsigned(IDX_W-1 downto 0);

  constant BALL_SPACING : integer := 1;
  constant BALL_R : integer := 13;
  constant RENDER_R : integer := 6;

  constant HIT_BOX : integer := 30;
  constant HIT_MAN : integer := 44;

  constant PLAYER_X : integer := 192;
  constant PLAYER_Y : integer := 332;
  constant HAND_OFF : integer := 28;

  constant HEAD_SPEED_Q2 : u2 := "10";
  constant ADD_BALL_EVERY_FRAMES : integer := 60;
  constant SHOT_SPEED_SHIFT : integer := 2;
  constant WIN_SCORE : integer := 13;
  constant AIM_STEP_EVERY_FRAMES : integer := 4;

  -- BONUS FEATURES: Special ball rewards
  constant RADIUS_BOMB_EVERY : integer := 5;
  constant BACKWARD_BOMB_EVERY : integer := 10;
  constant RADIUS_BOMB_RANGE : integer := 3;
  constant BACKWARD_BOMB_COUNT : integer := 6;

  -- ============================================================================
  -- 4) Aim LUT
  -- ============================================================================
  constant AIM_N : integer := 32;
  type lut32s is array(0 to AIM_N-1) of signed(15 downto 0);

  constant DX_Q6 : lut32s := (
    to_signed(   0,16), to_signed( 100,16), to_signed( 196,16), to_signed( 284,16),
    to_signed( 362,16), to_signed( 426,16), to_signed( 473,16), to_signed( 502,16),
    to_signed( 512,16), to_signed( 502,16), to_signed( 473,16), to_signed( 426,16),
    to_signed( 362,16), to_signed( 284,16), to_signed( 196,16), to_signed( 100,16),
    to_signed(   0,16), to_signed(-100,16), to_signed(-196,16), to_signed(-284,16),
    to_signed(-362,16), to_signed(-426,16), to_signed(-473,16), to_signed(-502,16),
    to_signed(-512,16), to_signed(-502,16), to_signed(-473,16), to_signed(-426,16),
    to_signed(-362,16), to_signed(-284,16), to_signed(-196,16), to_signed(-100,16)
  );

  constant DY_Q6 : lut32s := (
    to_signed(-512,16), to_signed(-502,16), to_signed(-473,16), to_signed(-426,16),
    to_signed(-362,16), to_signed(-284,16), to_signed(-196,16), to_signed(-100,16),
    to_signed(   0,16), to_signed( 100,16), to_signed( 196,16), to_signed( 284,16),
    to_signed( 362,16), to_signed( 426,16), to_signed( 473,16), to_signed( 502,16),
    to_signed( 512,16), to_signed( 502,16), to_signed( 473,16), to_signed( 426,16),
    to_signed( 362,16), to_signed( 284,16), to_signed( 196,16), to_signed( 100,16),
    to_signed(   0,16), to_signed(-100,16), to_signed(-196,16), to_signed(-284,16),
    to_signed(-362,16), to_signed(-426,16), to_signed(-473,16), to_signed(-502,16)
  );

  -- ============================================================================
  -- 5) Colors (RR GG BB) - Ball types
  -- ============================================================================
  constant C_BG      : std_logic_vector(5 downto 0) := "111111";
  constant C_OUTSIDE : std_logic_vector(5 downto 0) := "111111";
  constant C_PATH    : std_logic_vector(5 downto 0) := "000000";
  constant C_AIM     : std_logic_vector(5 downto 0) := "000000";

  constant C_RED     : std_logic_vector(5 downto 0) := "110000";
  constant C_GREEN   : std_logic_vector(5 downto 0) := "001100";
  constant C_BLUE    : std_logic_vector(5 downto 0) := "000011";
  constant C_YELLOW  : std_logic_vector(5 downto 0) := "111100";
  constant C_CYAN    : std_logic_vector(5 downto 0) := "001111";
  constant C_MAG     : std_logic_vector(5 downto 0) := "110011";

  -- Special ball colors
  -- Use a visible color (background is also white = "111111")
  constant C_RADIUS_BOMB : std_logic_vector(5 downto 0) := "111011";
  constant C_BACKWARD_BOMB : std_logic_vector(5 downto 0) := "010101";

  -- Ball type encoding: 0-5 = normal colors, 6 = radius bomb, 7 = backward bomb
  function color_from_id(id : u3) return std_logic_vector is
  begin
    case to_integer(id) is
      when 0 => return C_RED;
      when 1 => return C_GREEN;
      when 2 => return C_BLUE;
      when 3 => return C_YELLOW;
      when 4 => return C_CYAN;
      when 5 => return C_MAG;
      when 6 => return C_RADIUS_BOMB;
      when others => return C_BACKWARD_BOMB;
    end case;
  end function;

  function abs_s11(a : s11) return u11 is
  begin
    if a(10)='1' then
      return u11(unsigned(-a));
    else
      return u11(unsigned(a));
    end if;
  end function;

  function in_circle_u(dx : u11; dy : u11) return boolean is
    variable adx : integer;
    variable ady : integer;
    variable ylim : integer;
  begin
    adx := to_integer(dx);
    ady := to_integer(dy);

    if (adx > RENDER_R) or (ady > RENDER_R) then
      return false;
    end if;

    case adx is
      when 0 => ylim := 6;
      when 1 => ylim := 6;
      when 2 => ylim := 6;
      when 3 => ylim := 5;
      when 4 => ylim := 4;
      when 5 => ylim := 3;
      when others => ylim := 1;
    end case;

    return (ady <= ylim);
  end function;

  -- ============================================================================
  -- 6) Path handling - FIXED CLOSED PATH
  -- ============================================================================
  constant PATH_LEN : integer := 34;

  function wrap_path_idx(i : integer) return integer is
    variable r : integer;
  begin
    r := i mod PATH_LEN;
    if r < 0 then
      r := r + PATH_LEN;
    end if;
    return r;
  end function;

  -- ============================================================================
  -- 7) Tint functions
  -- ============================================================================
  function half2(a : std_logic_vector(1 downto 0)) return std_logic_vector is
    variable u : unsigned(1 downto 0);
  begin
    u := unsigned(a);
    return std_logic_vector(shift_right(u,1));
  end function;

  function tint_win(p : std_logic_vector(5 downto 0)) return std_logic_vector is
    variable r,g,b : std_logic_vector(1 downto 0);
  begin
    r := half2(p(5 downto 4));
    g := p(3 downto 2);
    b := half2(p(1 downto 0));
    if unsigned(g) < to_unsigned(2,2) then g := "10"; end if;
    return r & g & b;
  end function;

  function tint_lose(p : std_logic_vector(5 downto 0)) return std_logic_vector is
    variable r,g,b : std_logic_vector(1 downto 0);
  begin
    r := p(5 downto 4);
    g := half2(p(3 downto 2));
    b := half2(p(1 downto 0));
    if unsigned(r) < to_unsigned(2,2) then r := "10"; end if;
    return r & g & b;
  end function;

  -- ============================================================================
  -- 8) FIXED PATH (Constant circular path - optimized for XC6SLX9)
  -- ============================================================================
  type ux_arr is array(0 to PATH_LEN-1) of u10;
  type uy_arr is array(0 to PATH_LEN-1) of u9;

  constant PATH_X : ux_arr := (
    to_unsigned(332,10), to_unsigned(330,10), to_unsigned(323,10), to_unsigned(311,10),
    to_unsigned(295,10), to_unsigned(276,10), to_unsigned(254,10), to_unsigned(230,10),
    to_unsigned(205,10), to_unsigned(179,10), to_unsigned(154,10), to_unsigned(130,10),
    to_unsigned(108,10), to_unsigned(89,10), to_unsigned(73,10), to_unsigned(61,10),
    to_unsigned(54,10), to_unsigned(52,10), to_unsigned(54,10), to_unsigned(61,10),
    to_unsigned(73,10), to_unsigned(89,10), to_unsigned(108,10), to_unsigned(130,10),
    to_unsigned(154,10), to_unsigned(179,10), to_unsigned(205,10), to_unsigned(230,10),
    to_unsigned(254,10), to_unsigned(276,10), to_unsigned(295,10), to_unsigned(311,10),
    to_unsigned(323,10), to_unsigned(330,10)
  );

  constant PATH_Y : uy_arr := (
    to_unsigned(144,9), to_unsigned(170,9), to_unsigned(195,9), to_unsigned(218,9),
    to_unsigned(238,9), to_unsigned(256,9), to_unsigned(269,9), to_unsigned(279,9),
    to_unsigned(283,9), to_unsigned(283,9), to_unsigned(279,9), to_unsigned(269,9),
    to_unsigned(256,9), to_unsigned(238,9), to_unsigned(218,9), to_unsigned(195,9),
    to_unsigned(170,9), to_unsigned(144,9), to_unsigned(118,9), to_unsigned(93,9),
    to_unsigned(70,9), to_unsigned(50,9), to_unsigned(32,9), to_unsigned(19,9),
    to_unsigned(9,9), to_unsigned(5,9), to_unsigned(5,9), to_unsigned(9,9),
    to_unsigned(19,9), to_unsigned(32,9), to_unsigned(50,9), to_unsigned(70,9),
    to_unsigned(93,9), to_unsigned(118,9)
  );

  -- ============================================================================
  -- 9) RNG (LFSR)
  -- ============================================================================
  constant RNG_SEED : std_logic_vector(31 downto 0) := x"1ACEB00C";
  signal   lfsr     : std_logic_vector(31 downto 0) := RNG_SEED;

  function lfsr_step(x : std_logic_vector(31 downto 0)) return std_logic_vector is
    variable fb : std_logic;
  begin
    fb := x(31) xor x(21) xor x(1) xor x(0);
    return x(30 downto 0) & fb;
  end function;

  function make_entropy(
    key  : std_logic_vector(3 downto 0);
    head : u7;
    aim  : u5;
    framecnt : unsigned(7 downto 0);
    score    : unsigned(7 downto 0)
  ) return std_logic_vector is
    variable e : std_logic_vector(31 downto 0);
  begin
    e := (others => '0');
    e(3 downto 0)   := key;
    e(10 downto 4)  := std_logic_vector(head);
    e(15 downto 11) := std_logic_vector(aim);
    e(23 downto 16) := std_logic_vector(framecnt);
    e(31 downto 24) := std_logic_vector(score);
    return e;
  end function;

  procedure rng_advance(
    variable s : inout std_logic_vector(31 downto 0);
    constant entropy : in std_logic_vector(31 downto 0)
  ) is
  begin
    if s = x"00000000" then
      s := RNG_SEED;
    end if;
    s := lfsr_step(s xor entropy);
  end procedure;

  procedure rng_color6(
    variable s : inout std_logic_vector(31 downto 0);
    constant entropy : in std_logic_vector(31 downto 0);
    variable c : out u3
  ) is
    variable b1, b2 : unsigned(7 downto 0);
    variable val    : integer;
  begin
    rng_advance(s, entropy);
    b1 := unsigned(s(7 downto 0));

    if b1 < to_unsigned(252,8) then
      val := to_integer(b1) mod 6;
    else
      rng_advance(s, entropy);
      b2 := unsigned(s(7 downto 0));
      val := to_integer(b2) mod 6;
    end if;

    c := to_unsigned(val, 3);
  end procedure;

  -- ============================================================================
  -- 10) Game state
  -- ============================================================================
  type color_arr is array(0 to MAX_STORE-1) of u3;

  signal colors    : color_arr;
  signal chain_len : idx_t := (others=>'0');

  signal head_idx  : u7 := (others=>'0');
  signal head_frac : u2 := (others=>'0');

  type cx_arr is array(0 to MAX_STORE-1) of u10;
  type cy_arr is array(0 to MAX_STORE-1) of u9;
  signal ball_cx : cx_arr := (others => (others=>'0'));
  signal ball_cy : cy_arr := (others => (others=>'0'));

  signal aim_idx      : u5 := (others=>'0');
  signal aim_rate_cnt : unsigned(2 downto 0) := (others=>'0');
  signal hand_color   : u3 := (others=>'0');

  signal shot_active  : std_logic := '0';
  signal shot_color   : u3 := (others=>'0');
  signal shot_x_q     : signed(15 downto 0) := to_signed(PLAYER_X*64,16);
  signal shot_y_q     : signed(15 downto 0) := to_signed(PLAYER_Y*64,16);

  signal shot_hit_pending : std_logic := '0';
  signal shot_hit_idx     : idx_t := (others=>'0');
  signal shot_hit_sx      : signed(10 downto 0) := (others=>'0');
  signal shot_hit_sy      : signed(10 downto 0) := (others=>'0');

  signal shot_dir     : u5 := (others=>'0');

  signal fire_pending : std_logic := '0';
  signal key0_prev    : std_logic := '1';

  signal lose_flag    : std_logic := '0';
  signal win_flag     : std_logic := '0';
  signal lose_pending : std_logic := '0';
  signal score_cnt    : unsigned(7 downto 0) := (others=>'0');

  signal add_frame_cnt : unsigned(7 downto 0) := (others=>'0');
  signal spawn_pending : std_logic := '0';

  -- Special ball tracking
  signal destroyed_count : unsigned(7 downto 0) := (others=>'0');
  signal has_radius_bomb : std_logic := '0';
  signal has_backward_bomb : std_logic := '0';

  type st_t is (
    IDLE,
    INS_SHIFT, INS_WAIT,
    FIND_L, FIND_R, DECIDE,
    DEL_SHIFT, DEL_WAIT, BRIDGE,
    SCAN_INIT, SCAN_STEP, SCAN_FINAL,
    ADD_WAIT
  );
  signal st : st_t := IDLE;

  signal insert_pos : idx_t := (others=>'0');
  signal shift_k    : idx_t := (others=>'0');

  signal match_L : idx_t := (others=>'0');
  signal match_R : idx_t := (others=>'0');
  signal match_c : u3 := (others=>'0');

  signal del_L : idx_t := (others=>'0');
  signal del_R : idx_t := (others=>'0');

  signal scan_i    : idx_t := (others=>'0');
  signal run_start : idx_t := (others=>'0');
  signal run_len   : idx_t := (others=>'0');
  signal run_color : u3 := (others=>'0');

  signal color_comb : std_logic_vector(5 downto 0) := (others=>'0');

begin

  ScoreOut <= std_logic_vector(score_cnt);
  WinOut   <= win_flag;
  LoseOut  <= lose_flag;

  -- ============================================================================
  -- GAME UPDATE
  -- ============================================================================
  process(CLK_24MHz, RESET)
    variable i : integer;
    variable tmp3 : unsigned(2 downto 0);
    variable sx : s11;
    variable sy : s11;
    variable dx, dy : s11;
    variable adx, ady : u11;
    variable hit_found : boolean;
    variable hit_i     : integer;
    variable best_dist : integer;
    variable len_i : integer;
    variable removed : integer;
    variable new_score_i : integer;
    -- reward counters (special balls)
    variable old_destroyed_i : integer;
    variable new_destroyed_i : integer;
    variable bl, br : integer;
    variable idx0_i : integer;
    variable bx_u10 : u10;
    variable by_u9  : u9;
    variable idx_hit  : integer;
    variable idx_prev : integer;
    variable idx_next : integer;
    variable tx, ty : s12;
    variable vx, vy : s12;
    variable front_side : boolean;
    variable len_after : integer;
    variable dsum : integer;
    variable rng_v     : std_logic_vector(31 downto 0);
    variable entropy_v : std_logic_vector(31 downto 0);
    variable new_col   : u3;
    variable game_running : boolean;
    variable shot_x_next : signed(15 downto 0);
    variable shot_y_next : signed(15 downto 0);
    variable shot_x_use  : signed(15 downto 0);
    variable shot_y_use  : signed(15 downto 0);
    variable shot_act_use : boolean;
    variable spawn_pulse : boolean;
    variable head_calc : integer;
    variable spawn_pending_v : std_logic;
    variable is_special_ball : boolean;
    -- special-ball delete range (compute in integers to avoid signal read-after-write)
    variable sp_del_L_i : integer;
    variable sp_del_R_i : integer;
  begin
    if RESET='1' then

      chain_len <= to_unsigned(4, chain_len'length);
      colors(0) <= to_unsigned(0,3);
      colors(1) <= to_unsigned(1,3);
      colors(2) <= to_unsigned(2,3);
      colors(3) <= to_unsigned(3,3);
      for i in 4 to MAX_STORE-1 loop
        colors(i) <= to_unsigned(0,3);
      end loop;

      head_idx  <= (others=>'0');
      head_frac <= (others=>'0');

      aim_idx <= (others=>'0');
      aim_rate_cnt <= (others=>'0');

      lfsr <= RNG_SEED;
      hand_color <= to_unsigned(0,3);

      shot_active <= '0';
      shot_color <= to_unsigned(0,3);
      shot_x_q <= to_signed(PLAYER_X*64,16);
      shot_y_q <= to_signed(PLAYER_Y*64,16);
      shot_dir <= (others=>'0');
      shot_hit_idx <= (others=>'0');
      shot_hit_sx <= (others=>'0');
      shot_hit_sy <= (others=>'0');
      shot_hit_pending <= '0';

      fire_pending <= '0';
      key0_prev <= '1';

      lose_flag <= '0';
      win_flag  <= '0';
      lose_pending <= '0';
      score_cnt <= (others=>'0');
      destroyed_count <= (others=>'0');
      has_radius_bomb <= '0';
      has_backward_bomb <= '0';

      add_frame_cnt <= (others=>'0');
      spawn_pending <= '0';
      st <= IDLE;

    elsif rising_edge(CLK_24MHz) then

      if FrameTick='1' then

        game_running := (lose_flag='0') and (win_flag='0');

        rng_v     := lfsr;
        entropy_v := make_entropy(Key, head_idx, aim_idx, add_frame_cnt, score_cnt);

        shot_x_use := shot_x_q;
        shot_y_use := shot_y_q;
        shot_act_use := (shot_active = '1');

        spawn_pending_v := spawn_pending;
        if add_frame_cnt = to_unsigned(ADD_BALL_EVERY_FRAMES-1,8) then
          add_frame_cnt <= (others=>'0');
          spawn_pending_v := '1';
        else
          add_frame_cnt <= add_frame_cnt + 1;
        end if;

        spawn_pulse := (spawn_pending_v = '1') and (st = IDLE);

        if game_running then
          rng_advance(rng_v, entropy_v);
        end if;

        if game_running then
          if (key0_prev='1') and (Key(0)='0') then
            fire_pending <= '1';
          end if;
        end if;
        key0_prev <= Key(0);

        if game_running then

          head_frac <= (others=>'0');
          head_calc := to_integer(head_idx);
          if spawn_pulse then
            spawn_pending_v := '0';
            head_calc := head_calc + 1;
            if head_calc >= PATH_LEN then
              head_calc := head_calc - PATH_LEN;
            end if;
          end if;

          head_idx <= to_unsigned(head_calc, head_idx'length);


                -- ----------------------------------------------------------------
                -- LOSE condition (FIX)
                --   Do NOT lose just because the storage is full.
                --   Lose only when the chain has reached the end of the path AND
                --   there is no space to append a new ball.
                --   In this design, "end of path" is the last path index.
                -- ----------------------------------------------------------------
                if spawn_pulse and (to_integer(chain_len) >= MAX_STORE) and
                   (to_integer(head_idx) = PATH_LEN-1) then
                  lose_flag <= '1';
                end if;

          len_i := to_integer(chain_len);
          for i in 0 to MAX_STORE-1 loop
            if i < len_i then
              idx0_i := wrap_path_idx(head_calc - (i * BALL_SPACING));
              ball_cx(i) <= PATH_X(idx0_i);
              ball_cy(i) <= PATH_Y(idx0_i);
            end if;
          end loop;

          if (Key(1)='0') or (Key(2)='0') then
            if aim_rate_cnt = to_unsigned(AIM_STEP_EVERY_FRAMES-1,3) then
              aim_rate_cnt <= (others=>'0');
              if Key(1)='0' then
                if aim_idx = to_unsigned(0,5) then
                  aim_idx <= to_unsigned(AIM_N-1,5);
                else
                  aim_idx <= aim_idx - 1;
                end if;
              else
                if aim_idx = to_unsigned(AIM_N-1,5) then
                  aim_idx <= to_unsigned(0,5);
                else
                  aim_idx <= aim_idx + 1;
                end if;
              end if;
            else
              aim_rate_cnt <= aim_rate_cnt + 1;
            end if;
          else
            aim_rate_cnt <= (others=>'0');
          end if;

          if (fire_pending='1') and (shot_active='0') and (st=IDLE) then
            fire_pending <= '0';
            shot_active  <= '1';
            shot_dir     <= aim_idx;

            shot_x_q <= to_signed(PLAYER_X*64,16) + DX_Q6(to_integer(aim_idx)) + DX_Q6(to_integer(aim_idx));
            shot_y_q <= to_signed(PLAYER_Y*64,16) + DY_Q6(to_integer(aim_idx)) + DY_Q6(to_integer(aim_idx));

            shot_color <= hand_color;

            if has_radius_bomb = '1' then
              hand_color <= to_unsigned(6,3);
              has_radius_bomb <= '0';
            elsif has_backward_bomb = '1' then
              hand_color <= to_unsigned(7,3);
              has_backward_bomb <= '0';
            else
              rng_color6(rng_v, entropy_v, new_col);
              hand_color <= new_col;
            end if;
          end if;

          if st = IDLE then
            if spawn_pulse then
              if to_integer(chain_len) < MAX_STORE then
                rng_color6(rng_v, entropy_v, new_col);
                colors(to_integer(chain_len)) <= new_col;
                chain_len <= chain_len + 1;
                if shot_active='0' then
                  st <= ADD_WAIT;
                else
                  st <= IDLE;
                end if;
              else
                st <= IDLE;
              end if;
            end if;
          end if;

          if shot_active='1' then
            shot_x_next := shot_x_use + shift_left(DX_Q6(to_integer(shot_dir)), SHOT_SPEED_SHIFT);
            shot_y_next := shot_y_use + shift_left(DY_Q6(to_integer(shot_dir)), SHOT_SPEED_SHIFT);

            sx := to_signed(to_integer(shift_right(shot_x_next,6)),11);
            sy := to_signed(to_integer(shift_right(shot_y_next,6)),11);

            if (sx < to_signed(0,11)) or (sx >= to_signed(SCREEN_W,11)) or
               (sy < to_signed(0,11)) or (sy >= to_signed(SCREEN_H,11)) then
              shot_active <= '0';
              shot_hit_pending <= '0';
            else
              shot_x_q <= shot_x_next;
              shot_y_q <= shot_y_next;
              shot_x_use := shot_x_next;
              shot_y_use := shot_y_next;
            end if;
          end if;

          if (shot_active='1') and (shot_hit_pending='0') and (st=IDLE) then
            hit_found := false;
            best_dist := 999999;
            hit_i     := 0;

            len_i := to_integer(chain_len);
            for i in 0 to MAX_STORE-1 loop
              if i < len_i then
                bx_u10 := ball_cx(i);
                by_u9  := ball_cy(i);

                sx := to_signed(to_integer(shift_right(shot_x_use,6)),11);
                sy := to_signed(to_integer(shift_right(shot_y_use,6)),11);

                dx := sx - s11(signed(resize(bx_u10,11)));
                dy := sy - s11(signed(resize(by_u9,11)));

                adx := abs_s11(dx);
                ady := abs_s11(dy);

                if (adx <= to_unsigned(HIT_BOX,11)) and (ady <= to_unsigned(HIT_BOX,11)) then
                  dsum := to_integer(adx) + to_integer(ady);
                  if dsum <= HIT_MAN then
                    if dsum < best_dist then
                      best_dist := dsum;
                      hit_i := i;
                      hit_found := true;
                    end if;
                  end if;
                end if;
              end if;
            end loop;

            if hit_found then
              shot_hit_pending <= '1';
              shot_hit_idx <= to_unsigned(hit_i, shot_hit_idx'length);
              shot_hit_sx <= to_signed(to_integer(shift_right(shot_x_use,6)),11);
              shot_hit_sy <= to_signed(to_integer(shift_right(shot_y_use,6)),11);
            end if;
          end if;

          if st = ADD_WAIT then
            st <= IDLE;
          end if;

          if (shot_hit_pending='1') and (st=IDLE) then
            shot_active <= '0';
            shot_hit_pending <= '0';

            idx_hit := to_integer(shot_hit_idx);

            if idx_hit < to_integer(chain_len) then
              bx_u10 := ball_cx(idx_hit);
              by_u9  := ball_cy(idx_hit);

              tx := s12(resize(shot_hit_sx,12)) - s12(signed(resize(bx_u10,12)));
              ty := s12(resize(shot_hit_sy,12)) - s12(signed(resize(by_u9,12)));

              idx_prev := idx_hit - 1;
              idx_next := idx_hit + 1;

              front_side := false;

              if (idx_hit > 0) and (idx_next < to_integer(chain_len)) then
                vx := s12(signed(resize(ball_cx(idx_next),12))) - s12(signed(resize(ball_cx(idx_prev),12)));
                vy := s12(signed(resize(ball_cy(idx_next),12))) - s12(signed(resize(ball_cy(idx_prev),12)));

                if ((tx * vx) + (ty * vy)) > to_signed(0,12) then
                  front_side := true;
                end if;
              elsif idx_hit = 0 then
                front_side := true;
              end if;

              is_special_ball := (shot_color = to_unsigned(6,3)) or (shot_color = to_unsigned(7,3));

              if is_special_ball then
                -- Compute deletion bounds with variables (signals update next cycle).
                sp_del_L_i := idx_hit;
                sp_del_R_i := idx_hit;

                if shot_color = to_unsigned(6,3) then
                  -- RADIUS_BOMB: delete +/- RADIUS_BOMB_RANGE around hit index.
                  sp_del_L_i := idx_hit - RADIUS_BOMB_RANGE;
                  if sp_del_L_i < 0 then
                    sp_del_L_i := 0;
                  end if;

                  sp_del_R_i := idx_hit + RADIUS_BOMB_RANGE;
                  if sp_del_R_i >= to_integer(chain_len) then
                    sp_del_R_i := to_integer(chain_len) - 1;
                  end if;
                else
                  -- BACKWARD_BOMB: delete BACKWARD_BOMB_COUNT balls behind the hit.
                  sp_del_L_i := idx_hit - BACKWARD_BOMB_COUNT;
                  if sp_del_L_i < 0 then
                    sp_del_L_i := 0;
                  end if;
                  sp_del_R_i := idx_hit;
                end if;

                del_L   <= to_unsigned(sp_del_L_i, del_L'length);
                del_R   <= to_unsigned(sp_del_R_i, del_R'length);
                shift_k <= to_unsigned(sp_del_R_i + 1, shift_k'length);
                st <= DEL_SHIFT;
              else
                if front_side then
                  insert_pos <= to_unsigned(idx_hit, insert_pos'length);
                else
                  insert_pos <= to_unsigned(idx_hit+1, insert_pos'length);
                end if;

                shift_k <= chain_len;
                st <= INS_SHIFT;
              end if;
            end if;
          end if;

          case st is
            when IDLE =>
              null;

			when INS_SHIFT =>
			  -- If storage is full, do NOT declare LOSE here.
			  -- Simply cancel the insertion to avoid overflow.
			  if to_integer(chain_len) >= MAX_STORE then
			    st <= IDLE;
			  else
			    if shift_k = insert_pos then
			      colors(to_integer(insert_pos)) <= shot_color;
			      chain_len <= chain_len + 1;
			      st <= INS_WAIT;
			    else
			      colors(to_integer(shift_k)) <= colors(to_integer(shift_k - 1));
			      shift_k <= shift_k - 1;
			    end if;
			  end if;


            when INS_WAIT =>
              match_c <= shot_color;
              match_L <= insert_pos;
              match_R <= insert_pos;
              st <= FIND_L;

            when FIND_L =>
              bl := to_integer(match_L) - 1;
              if (bl < 0) or (colors(bl) /= match_c) then
                st <= FIND_R;
              else
                match_L <= to_unsigned(bl, match_L'length);
              end if;

            when FIND_R =>
              br := to_integer(match_R) + 1;
              if (br >= to_integer(chain_len)) or (colors(br) /= match_c) then
                st <= DECIDE;
              else
                match_R <= to_unsigned(br, match_R'length);
              end if;

            when DECIDE =>
              len_after := to_integer(match_R) - to_integer(match_L) + 1;
              if len_after >= 3 then
                del_L   <= match_L;
                del_R   <= match_R;
                shift_k <= match_R + 1;
                st <= DEL_SHIFT;
              else
                st <= SCAN_INIT;
              end if;

            when DEL_SHIFT =>
              removed := to_integer(del_R) - to_integer(del_L) + 1;

              if shift_k >= chain_len then
                new_score_i := to_integer(score_cnt) + removed;
                if new_score_i > 255 then
                  new_score_i := 255;
                end if;
                score_cnt <= to_unsigned(new_score_i,8);

                -- ----------------------------------------------------------------
                -- Special ball rewards (FIX)
                --   The old code compared the *previous* destroyed_count (signal)
                --   which delays rewards and also made BACKWARD_BOMB very unlikely.
                --   Here we evaluate using the updated value and reward on crossing
                --   each threshold: every 5 deletes => radius, every 10 => backward.
                -- ----------------------------------------------------------------
                old_destroyed_i := to_integer(destroyed_count);
                new_destroyed_i := old_destroyed_i + removed;
                if new_destroyed_i > 255 then
                  new_destroyed_i := 255;
                end if;
                destroyed_count <= to_unsigned(new_destroyed_i, destroyed_count'length);

                if (has_radius_bomb = '0') and
                   ((new_destroyed_i / RADIUS_BOMB_EVERY) > (old_destroyed_i / RADIUS_BOMB_EVERY)) then
                  has_radius_bomb <= '1';
                end if;

                if (has_backward_bomb = '0') and
                   ((new_destroyed_i / BACKWARD_BOMB_EVERY) > (old_destroyed_i / BACKWARD_BOMB_EVERY)) then
                  has_backward_bomb <= '1';
                end if;

                if new_score_i >= WIN_SCORE then
                  win_flag <= '1';
                end if;

                chain_len <= chain_len - to_unsigned(removed, chain_len'length);
                st <= DEL_WAIT;
              else
                colors(to_integer(shift_k - to_unsigned(removed, shift_k'length))) <= colors(to_integer(shift_k));
                shift_k <= shift_k + 1;
              end if;

            when DEL_WAIT =>
              st <= BRIDGE;

            when BRIDGE =>
              bl := to_integer(del_L) - 1;
              br := to_integer(del_L);
              if (bl < 0) or (br >= to_integer(chain_len)) then
                st <= SCAN_INIT;
              elsif colors(bl) = colors(br) then
                match_c <= colors(bl);
                match_L <= to_unsigned(bl, match_L'length);
                match_R <= to_unsigned(br, match_R'length);
                st <= FIND_L;
              else
                st <= SCAN_INIT;
              end if;

            when SCAN_INIT =>
              if to_integer(chain_len) < 3 then
                st <= IDLE;
              else
                scan_i    <= to_unsigned(0, scan_i'length);
                run_start <= to_unsigned(0, run_start'length);
                run_len   <= to_unsigned(1, run_len'length);
                run_color <= colors(0);
                st <= SCAN_STEP;
              end if;

            when SCAN_STEP =>
              if scan_i >= (chain_len-1) then
                st <= SCAN_FINAL;
              else
                if colors(to_integer(scan_i+1)) = run_color then
                  run_len <= run_len + 1;
                  scan_i  <= scan_i + 1;
                else
                  if to_integer(run_len) >= 3 then
                    del_L   <= run_start;
                    del_R   <= run_start + run_len - 1;
                    shift_k <= run_start + run_len;
                    st <= DEL_SHIFT;
                  else
                    scan_i    <= scan_i + 1;
                    run_start <= scan_i + 1;
                    run_len   <= to_unsigned(1, run_len'length);
                    run_color <= colors(to_integer(scan_i+1));
                  end if;
                end if;
              end if;

            when SCAN_FINAL =>
              if to_integer(run_len) >= 3 then
                del_L   <= run_start;
                del_R   <= run_start + run_len - 1;
                shift_k <= run_start + run_len;
                st <= DEL_SHIFT;
              else
                st <= IDLE;
              end if;

            when others =>
              st <= IDLE;
          end case;

        else
          fire_pending <= '0';
          shot_active <= '0';
          shot_hit_pending <= '0';
        end if;

        lfsr <= rng_v;
        spawn_pending <= spawn_pending_v;
      end if;

      DebugLeds(7) <= lose_flag;
      DebugLeds(6) <= win_flag;
      DebugLeds(5) <= has_radius_bomb;
      DebugLeds(4) <= has_backward_bomb;
      DebugLeds(3 downto 0) <= std_logic_vector(score_cnt(3 downto 0));

    end if;
  end process;

  -- ============================================================================
  -- RENDER
  -- ============================================================================
  process(ScanlineX, ScanlineY,
          chain_len, colors, ball_cx, ball_cy,
          shot_active, shot_x_q, shot_y_q, shot_color,
          aim_idx, hand_color, lose_flag, win_flag)
    variable xg, yg : integer;
    variable x, y   : integer;
    variable pix    : std_logic_vector(5 downto 0);

    variable i : integer;
    variable len_i : integer;

    variable sx_i, sy_i : integer;

    variable stepx, stepy : integer;
    variable ax, ay : integer;
    variable tipx, tipy : integer;

    variable dxs, dys : s11;
    variable adx, ady : u11;
  begin
    xg := to_integer(unsigned(ScanlineX));
    yg := to_integer(unsigned(ScanlineY));

    pix := C_OUTSIDE;

    if (xg >= OFFX) and (xg < OFFX + SCREEN_W) and (yg >= OFFY) and (yg < OFFY + SCREEN_H) then
      x := xg - OFFX;
      y := yg - OFFY;

      pix := C_BG;

      for i in 0 to PATH_LEN-1 loop
        if (x = to_integer(PATH_X(i))) and (y = to_integer(PATH_Y(i))) then
          pix := C_PATH;
        end if;
      end loop;

      len_i := to_integer(chain_len);
      for i in 0 to MAX_STORE-1 loop
        if i < len_i then
          dxs := to_signed(x,11) - s11(signed(resize(ball_cx(i), 11)));
          dys := to_signed(y,11) - s11(signed(resize(ball_cy(i), 11)));
          adx := abs_s11(dxs);
          ady := abs_s11(dys);
          if in_circle_u(adx, ady) then
            pix := color_from_id(colors(i));
          end if;
        end if;
      end loop;

      if shot_active='1' then
        sx_i := to_integer(shift_right(shot_x_q,6));
        sy_i := to_integer(shift_right(shot_y_q,6));
        dxs := to_signed(x,11) - to_signed(sx_i,11);
        dys := to_signed(y,11) - to_signed(sy_i,11);
        adx := abs_s11(dxs);
        ady := abs_s11(dys);
        if in_circle_u(adx, ady) then
          pix := color_from_id(shot_color);
        end if;
      end if;

      dxs := to_signed(x,11) - to_signed(PLAYER_X,11);
      dys := to_signed(y,11) - to_signed(PLAYER_Y,11);
      if in_circle_u(abs_s11(dxs), abs_s11(dys)) then
        pix := C_PATH;
      end if;

      dxs := to_signed(x,11) - to_signed(PLAYER_X + HAND_OFF,11);
      dys := to_signed(y,11) - to_signed(PLAYER_Y,11);
      if in_circle_u(abs_s11(dxs), abs_s11(dys)) then
        pix := color_from_id(hand_color);
      end if;

      stepx := to_integer(shift_right(DX_Q6(to_integer(aim_idx)), 8));
      stepy := to_integer(shift_right(DY_Q6(to_integer(aim_idx)), 8));
      ax := PLAYER_X;
      ay := PLAYER_Y;
      for i in 0 to 6 loop
        ax := ax + stepx;
        ay := ay + stepy;
        if (x = ax) and (y = ay) then pix := C_AIM; end if;
      end loop;

      tipx := PLAYER_X + to_integer(shift_right(DX_Q6(to_integer(aim_idx)), 2));
      tipy := PLAYER_Y + to_integer(shift_right(DY_Q6(to_integer(aim_idx)), 2));
      if ( (x = tipx and (y = tipy or y = tipy-1 or y = tipy+1)) or
           (y = tipy and (x = tipx or x = tipx-1 or x = tipx+1)) ) then
        pix := C_AIM;
      end if;

      if win_flag='1' then
        pix := tint_win(pix);
      elsif lose_flag='1' then
        pix := tint_lose(pix);
      end if;

    end if;

    color_comb <= pix;
  end process;

  process(CLK_24MHz, RESET)
  begin
    if RESET='1' then
      ColorOut <= (others=>'0');
    elsif rising_edge(CLK_24MHz) then
      ColorOut <= color_comb;
    end if;
  end process;

end rtl;

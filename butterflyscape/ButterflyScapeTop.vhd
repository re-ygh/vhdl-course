library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ButterflyScapeTop is
  Port(
    CLOCK_24   : in  std_logic;
    RESET_N    : in  std_logic;

    VGA_B      : out std_logic_vector(1 downto 0);
    VGA_G      : out std_logic_vector(1 downto 0);
    VGA_HS     : out std_logic;
    VGA_R      : out std_logic_vector(1 downto 0);
    VGA_VS     : out std_logic;

    Key        : in  std_logic_vector(3 downto 0);
    SW         : in  std_logic_vector(7 downto 0);

    Leds       : out std_logic_vector(7 downto 0);

    outseg        : out bit_vector(3 downto 0);
    sevensegments : out bit_vector(7 downto 0)
  );
end;

architecture rtl of ButterflyScapeTop is

  component VGA_controller
    port(
      CLK_24MHz  : in  std_logic;
      RESET      : in  std_logic;

      VS         : out std_logic;
      HS         : out std_logic;

      RED        : out std_logic_vector(1 downto 0);
      GREEN      : out std_logic_vector(1 downto 0);
      BLUE       : out std_logic_vector(1 downto 0);

      ColorIN    : in  std_logic_vector(5 downto 0);

      ScanlineX  : out std_logic_vector(10 downto 0);
      ScanlineY  : out std_logic_vector(10 downto 0);

      FrameTick  : out std_logic
    );
  end component;

  component ButterflyScapeGame
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
  end component;

  signal ScanlineX, ScanlineY : std_logic_vector(10 downto 0);
  signal ColorTable           : std_logic_vector(5 downto 0);
  signal FrameTick            : std_logic;

  signal dbg                  : std_logic_vector(7 downto 0);
  signal score8               : std_logic_vector(7 downto 0);
  signal win_f, lose_f        : std_logic;

  -- 7seg mux
  signal seg_selectors : bit_vector(3 downto 0) := "1110";
  signal seg0, seg1, seg2, seg3 : bit_vector(7 downto 0) := x"FF";

  signal reset_hi : std_logic;

  function seg_digit(d : integer) return bit_vector is
  begin
    case d is
      when 0 => return x"C0";
      when 1 => return x"F9";
      when 2 => return x"A4";
      when 3 => return x"B0";
      when 4 => return x"99";
      when 5 => return x"92";
      when 6 => return x"82";
      when 7 => return x"F8";
      when 8 => return x"80";
      when 9 => return x"98";
      when others => return x"FF";
    end case;
  end function;

  constant SEG_BLANK : bit_vector(7 downto 0) := x"FF";

  constant SEG_L : bit_vector(7 downto 0) := x"C7";
  constant SEG_O : bit_vector(7 downto 0) := x"C0";
  constant SEG_S : bit_vector(7 downto 0) := x"92";
  constant SEG_E : bit_vector(7 downto 0) := x"86";

  -- approximate letters for BORD on 7seg
  constant SEG_B : bit_vector(7 downto 0) := x"83"; -- b
  constant SEG_R : bit_vector(7 downto 0) := x"AF"; -- r
  constant SEG_D : bit_vector(7 downto 0) := x"A1"; -- d

  -- Last 2 digits of each student's ID (set these four constants to your IDs)
  -- Example: if IDs end with 23 and 47, then:
  --   S1_TENS = 2, S1_ONES = 3, S2_TENS = 4, S2_ONES = 7
  constant S1_TENS : integer := 4;
  constant S1_ONES : integer := 4;
  constant S2_TENS : integer := 5;
  constant S2_ONES : integer := 8;

begin
  reset_hi <= not RESET_N;

  MAP0: VGA_controller
    port map(
      CLK_24MHz => CLOCK_24,
      RESET     => reset_hi,

      VS        => VGA_VS,
      HS        => VGA_HS,

      RED       => VGA_R,
      GREEN     => VGA_G,
      BLUE      => VGA_B,

      ColorIN   => ColorTable,

      ScanlineX => ScanlineX,
      ScanlineY => ScanlineY,

      FrameTick => FrameTick
    );

  MAP1: ButterflyScapeGame
    port map(
      CLK_24MHz => CLOCK_24,
      RESET     => reset_hi,
      FrameTick => FrameTick,

      Key       => Key,

      ScanlineX => ScanlineX,
      ScanlineY => ScanlineY,

      ColorOut  => ColorTable,

      ScoreOut  => score8,
      WinOut    => win_f,
      LoseOut   => lose_f,

      DebugLeds => dbg
    );

  Leds <= dbg;

  -- mux rotate
  process(CLOCK_24, reset_hi)
    variable counter : integer range 0 to 5000 := 0;
  begin
    if reset_hi='1' then
      counter := 0;
      seg_selectors <= "1110";
    elsif rising_edge(CLOCK_24) then
      counter := counter + 1;
      if counter = 4999 then
        counter := 0;
        seg_selectors <= seg_selectors(0) & seg_selectors(3 downto 1);
      end if;
    end if;
  end process;

  outseg <= seg_selectors;

  process(seg_selectors, seg0, seg1, seg2, seg3)
  begin
    case seg_selectors is
      when "1110" => sevensegments <= seg0;
      when "1101" => sevensegments <= seg1;
      when "1011" => sevensegments <= seg2;
      when "0111" => sevensegments <= seg3;
      when others => sevensegments <= x"FF";
    end case;
  end process;

  -- display content
  -- Requirement:
  --   - After reset / during normal play: show last 2 digits of both students' IDs.
  --   - After game ends: show WIN or LOSE.
  process(win_f, lose_f)
  begin
    if win_f='1' then
      -- B O R D
      seg0 <= SEG_B;
      seg1 <= SEG_O;
      seg2 <= SEG_R;
      seg3 <= SEG_D;
    elsif lose_f='1' then
      -- L O S E
      seg0 <= SEG_L;
      seg1 <= SEG_O;
      seg2 <= SEG_S;
      seg3 <= SEG_E;
    else
      -- Show last 2 digits of each student's ID:
      -- left two digits: student 1, right two digits: student 2
      seg0 <= seg_digit(S1_TENS);
      seg1 <= seg_digit(S1_ONES);
      seg2 <= seg_digit(S2_TENS);
      seg3 <= seg_digit(S2_ONES);
    end if;
  end process;

end rtl;

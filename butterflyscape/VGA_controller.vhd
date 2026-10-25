library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity VGA_controller is
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
end VGA_controller;

architecture rtl of VGA_controller is
  -- 640x480@60Hz timing (works fine with 24MHz too)
  constant HDisplayArea : integer := 640;
  constant HLimit       : integer := 800;
  constant HFrontPorch  : integer := 16;
  constant HBackPorch   : integer := 48;
  constant HSyncWidth   : integer := 96;

  constant VDisplayArea : integer := 480;
  constant VLimit       : integer := 525;
  constant VFrontPorch  : integer := 10;
  constant VBackPorch   : integer := 33;
  constant VSyncWidth   : integer := 2;

  signal CurrentHPos : unsigned(10 downto 0) := (others=>'0');
  signal CurrentVPos : unsigned(10 downto 0) := (others=>'0');

  signal HBlank, VBlank, Blank : std_logic := '1';
  signal frame_tick_r : std_logic := '0';

begin

  process(CLK_24MHz, RESET)
  begin
    if RESET='1' then
      CurrentHPos <= (others=>'0');
      CurrentVPos <= (others=>'0');
      frame_tick_r <= '0';
    elsif rising_edge(CLK_24MHz) then
      frame_tick_r <= '0';

      if CurrentHPos < to_unsigned(HLimit-1, 11) then
        CurrentHPos <= CurrentHPos + 1;
      else
        CurrentHPos <= (others=>'0');

        if CurrentVPos < to_unsigned(VLimit-1, 11) then
          CurrentVPos <= CurrentVPos + 1;
        else
          CurrentVPos <= (others=>'0');
        end if;
      end if;

      -- one pulse per full frame (start of counter)
      if (CurrentHPos = to_unsigned(0,11)) and (CurrentVPos = to_unsigned(0,11)) then
        frame_tick_r <= '1';
      end if;
    end if;
  end process;

  FrameTick <= frame_tick_r;

  -- Sync
  HS <= '0' when CurrentHPos < to_unsigned(HSyncWidth,11) else '1';
  VS <= '0' when CurrentVPos < to_unsigned(VSyncWidth,11) else '1';

  -- Blanking
  HBlank <= '0' when (CurrentHPos >= to_unsigned(HSyncWidth + HFrontPorch,11)) and
                    (CurrentHPos <  to_unsigned(HSyncWidth + HFrontPorch + HDisplayArea,11))
           else '1';

  VBlank <= '0' when (CurrentVPos >= to_unsigned(VSyncWidth + VFrontPorch,11)) and
                    (CurrentVPos <  to_unsigned(VSyncWidth + VFrontPorch + VDisplayArea,11))
           else '1';

  Blank <= '1' when (HBlank='1') or (VBlank='1') else '0';

  -- Visible coordinates
  ScanlineX <= std_logic_vector(CurrentHPos - to_unsigned(HSyncWidth + HFrontPorch,11)) when Blank='0'
               else (others=>'0');

  ScanlineY <= std_logic_vector(CurrentVPos - to_unsigned(VSyncWidth + VFrontPorch,11)) when Blank='0'
               else (others=>'0');

  -- Pixel output
  RED   <= ColorIN(5 downto 4) when Blank='0' else "00";
  GREEN <= ColorIN(3 downto 2) when Blank='0' else "00";
  BLUE  <= ColorIN(1 downto 0) when Blank='0' else "00";

end rtl;

-- ============================================================================
--  Entity: REG
--  Description:
--    16x16-bit register file with one Valid bit per entry and the following
--    operations (each asserted for one clock):
--      Insert, Delete, Search, Count, Reverse, Sort,
--      ShiftLeft (rotate), ShiftRight (rotate),
--      Clear (synchronous reset), Get.
--
--  Output protocol:
--    - DataOut is meaningful only when Valid='1'.
--    - Valid is asserted for exactly one clock when an output-producing command
--      completes successfully (and for Count always, because 0 is still valid).
--    - Search/Get produce Valid='0' if no result is available.
--
--  Timing:
--    - Reset: asynchronous, active high.
--    - Clear: synchronous, active high (highest priority among commands).
--    - All other commands are sampled at rising edge of Clock.
--
--  Assumption (documented in report):
--    Only one command is asserted at a time. If multiple commands are asserted
--    simultaneously, the priority order implemented here will apply.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.reg_pkg.all;

entity REG is
  port (
    Clock      : in  std_logic; -- clock
    Reset      : in  std_logic; -- asynchronous reset
    DataIn     : in  std_logic_vector(15 downto 0); -- input data (or index for Get)
    Insert     : in  std_logic; -- insert DataIn at first available space
    Delete     : in  std_logic; -- delete first occurrence of DataIn
    Search     : in  std_logic; -- find index of DataIn (first occurrence)
    Count      : in  std_logic; -- count how many times DataIn appears in register
    Reverse    : in  std_logic; -- reverse the register
    ShiftLeft  : in  std_logic; -- shift and rotate to left
    ShiftRight : in  std_logic; -- shift and rotate to right
    Clear      : in  std_logic; -- synchronous reset
    Get        : in  std_logic; -- Use DataIn as Index and send out Data(DataIn) if possible
    Sort       : in  std_logic; -- sort the register
    DataOut    : out std_logic_vector(15 downto 0); -- output data
    Valid      : out std_logic  -- 1 for one clock if output is valid
  );
end entity;

architecture rtl of REG is
  signal regs_s    : reg_array_t := (others => (others => '0'));
  signal valids_s  : valid_vec_t := (others => '0');

  signal dataout_r : std_logic_vector(15 downto 0) := (others => '0');
  signal valid_r   : std_logic := '0';
begin
  DataOut <= dataout_r;
  Valid   <= valid_r;

  process (Clock, Reset)
    variable regs_v    : reg_array_t;
    variable valids_v  : valid_vec_t;
    variable idx       : integer;
    variable c         : integer;
    variable get_idx   : integer;
  begin
    if Reset = '1' then
      regs_s    <= (others => (others => '0'));
      valids_s  <= (others => '0');
      dataout_r <= (others => '0');
      valid_r   <= '0';

    elsif rising_edge(Clock) then
      -- Default: no new output this cycle
      valid_r <= '0';

      regs_v   := regs_s;
      valids_v := valids_s;

      -- Command priority:
      --   1) Clear
      --   2) Insert
      --   3) Delete
      --   4) Search
      --   5) Count
      --   6) Get
      --   7) Reverse
      --   8) ShiftLeft
      --   9) ShiftRight
      --  10) Sort
      if Clear = '1' then
        regs_v    := (others => (others => '0'));
        valids_v  := (others => '0');
        dataout_r <= (others => '0');
        valid_r   <= '0';

      elsif Insert = '1' then
        idx := first_invalid_index(valids_v);
        if idx /= -1 then
          regs_v(idx)   := DataIn;
          valids_v(idx) := '1';
        end if;

      elsif Delete = '1' then
        idx := first_match_index(regs_v, valids_v, DataIn);
        if idx /= -1 then
          valids_v(idx) := '0';
          regs_v(idx)   := (others => '0'); -- optional clear for clean waveform
        end if;

      elsif Search = '1' then
        idx := first_match_index(regs_v, valids_v, DataIn);
        if idx /= -1 then
          dataout_r <= std_logic_vector(to_unsigned(idx, 16));
          valid_r   <= '1';
        else
          -- not found => output not valid (Valid stays '0')
          valid_r   <= '0';
        end if;

      elsif Count = '1' then
        c         := count_match(regs_v, valids_v, DataIn);
        dataout_r <= std_logic_vector(to_unsigned(c, 16));
        valid_r   <= '1';

      elsif Get = '1' then
        get_idx := to_integer(unsigned(DataIn));
        if (get_idx >= 0) and (get_idx < REG_DEPTH) then
          if valids_v(get_idx) = '1' then
            dataout_r <= regs_v(get_idx);
            valid_r   <= '1';
          end if;
        end if;

      elsif Reverse = '1' then
        reverse_inplace(regs_v, valids_v);

      elsif ShiftLeft = '1' then
        rotate_left_inplace(regs_v, valids_v);

      elsif ShiftRight = '1' then
        rotate_right_inplace(regs_v, valids_v);

      elsif Sort = '1' then
        sort_inplace(regs_v, valids_v);

      else
        null;
      end if;

      regs_s   <= regs_v;
      valids_s <= valids_v;
    end if;
  end process;

end architecture;

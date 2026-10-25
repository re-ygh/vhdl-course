-- ============================================================================
--  Package: reg_pkg
--  Description:
--    Common types and utility subprograms for the REG mini-project.
--    * 16 x 16-bit register array
--    * One Valid bit per entry
--    * Helper functions/procedures: insert helpers, search/count, reverse/rotate,
--      and in-place sort (unsigned, invalid entries moved to end).
--
--  Notes:
--    - Written in VHDL-93 style and intended to compile in Active-HDL.
--    - All comparisons in sort are unsigned.
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package reg_pkg is
  constant REG_DEPTH : integer := 16;

  subtype reg_data_t  is std_logic_vector(15 downto 0);
  type    reg_array_t is array (0 to REG_DEPTH-1) of reg_data_t;

  subtype valid_vec_t is std_logic_vector(REG_DEPTH-1 downto 0); -- bit i => entry i

  -- Returns first index i such that valids(i)='0'. If none, returns -1.
  function first_invalid_index(valids : valid_vec_t) return integer;

  -- Returns first index i such that valids(i)='1' and regs(i)=data. If none, returns -1.
  function first_match_index(
    regs   : reg_array_t;
    valids : valid_vec_t;
    data   : reg_data_t
  ) return integer;

  -- Counts number of occurrences of data among valid entries.
  function count_match(
    regs   : reg_array_t;
    valids : valid_vec_t;
    data   : reg_data_t
  ) return integer;

  -- In-place operations on (regs, valids)
  procedure reverse_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  );

  procedure rotate_left_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  );

  procedure rotate_right_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  );

  -- Sort ascending (unsigned) for valid entries; invalid entries are pushed to the end.
  procedure sort_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  );
end package;

package body reg_pkg is
  function first_invalid_index(valids : valid_vec_t) return integer is
    variable idx : integer := -1;
  begin
    for i in 0 to REG_DEPTH-1 loop
      if valids(i) = '0' then
        idx := i;
        exit;
      end if;
    end loop;
    return idx;
  end function;

  function first_match_index(
    regs   : reg_array_t;
    valids : valid_vec_t;
    data   : reg_data_t
  ) return integer is
    variable idx : integer := -1;
  begin
    for i in 0 to REG_DEPTH-1 loop
      if (valids(i) = '1') and (regs(i) = data) then
        idx := i;
        exit;
      end if;
    end loop;
    return idx;
  end function;

  function count_match(
    regs   : reg_array_t;
    valids : valid_vec_t;
    data   : reg_data_t
  ) return integer is
    variable c : integer := 0;
  begin
    for i in 0 to REG_DEPTH-1 loop
      if (valids(i) = '1') and (regs(i) = data) then
        c := c + 1;
      end if;
    end loop;
    return c;
  end function;

  procedure reverse_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  ) is
    variable tmp_regs   : reg_array_t;
    variable tmp_valids : valid_vec_t;
  begin
    for i in 0 to REG_DEPTH-1 loop
      tmp_regs(i)   := regs(REG_DEPTH-1-i);
      tmp_valids(i) := valids(REG_DEPTH-1-i);
    end loop;
    regs   := tmp_regs;
    valids := tmp_valids;
  end procedure;

  procedure rotate_left_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  ) is
    variable first_reg   : reg_data_t;
    variable first_valid : std_logic;
  begin
    first_reg   := regs(0);
    first_valid := valids(0);

    for i in 0 to REG_DEPTH-2 loop
      regs(i)   := regs(i+1);
      valids(i) := valids(i+1);
    end loop;

    regs(REG_DEPTH-1)   := first_reg;
    valids(REG_DEPTH-1) := first_valid;
  end procedure;

  procedure rotate_right_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  ) is
    variable last_reg   : reg_data_t;
    variable last_valid : std_logic;
  begin
    last_reg   := regs(REG_DEPTH-1);
    last_valid := valids(REG_DEPTH-1);

    for i in REG_DEPTH-1 downto 1 loop
      regs(i)   := regs(i-1);
      valids(i) := valids(i-1);
    end loop;

    regs(0)   := last_reg;
    valids(0) := last_valid;
  end procedure;

  procedure sort_inplace(
    variable regs   : inout reg_array_t;
    variable valids : inout valid_vec_t
  ) is
    variable tmp_reg   : reg_data_t;
    variable tmp_valid : std_logic;
  begin
    -- Bubble-sort with custom comparison:
    --   1) Valid entries come before invalid entries.
    --   2) Among valid entries, ascending unsigned order.
    for pass in 0 to REG_DEPTH-2 loop
      for i in 0 to REG_DEPTH-2-pass loop
        if (valids(i) = '0') and (valids(i+1) = '1') then
          -- Swap to move valid entry left
          tmp_reg        := regs(i);
          regs(i)        := regs(i+1);
          regs(i+1)      := tmp_reg;

          tmp_valid      := valids(i);
          valids(i)      := valids(i+1);
          valids(i+1)    := tmp_valid;

        elsif (valids(i) = '1') and (valids(i+1) = '1') then
          if unsigned(regs(i)) > unsigned(regs(i+1)) then
            tmp_reg     := regs(i);
            regs(i)     := regs(i+1);
            regs(i+1)   := tmp_reg;
          end if;
          -- valids remain '1'/'1'
        end if;
      end loop;
    end loop;
  end procedure;

end package body;

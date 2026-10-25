-- ============================================================================
--  Testbench: tb_reg
--  Goals:
--    - Exercise all commands of REG:
--        Insert/Delete/Search/Count/Reverse/Sort/ShiftLeft/ShiftRight/Clear/Get
--    - Check timing: Valid pulses one clock and DataOut changes accordingly.
--    - Validate internal state indirectly using Get (full sweep of 16 indices).
--
--  How to use in Active-HDL:
--    1) Compile order: reg_pkg.vhd, reg.vhd, tb_reg.vhd
--    2) Set tb_reg as top-level and run.
--    3) If all assertions pass, simulation ends with "ALL TESTS PASSED".
-- ============================================================================
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.reg_pkg.all;

entity reg_TB is
end entity;

architecture sim of reg_TB is
  constant CLK_PERIOD : time := 10 ns;

  signal Clock      : std_logic := '0';
  signal Reset      : std_logic := '0';
  signal DataIn     : std_logic_vector(15 downto 0) := (others => '0');

  signal Insert     : std_logic := '0';
  signal Delete     : std_logic := '0';
  signal Search     : std_logic := '0';
  signal Count      : std_logic := '0';
  signal Reverse    : std_logic := '0';
  signal ShiftLeft  : std_logic := '0';
  signal ShiftRight : std_logic := '0';
  signal Clear      : std_logic := '0';
  signal Get        : std_logic := '0';
  signal Sort       : std_logic := '0';

  signal DataOut    : std_logic_vector(15 downto 0);
  signal Valid      : std_logic;

  -- Reference model (expected state)
  signal done       : std_logic := '0';
begin
  -- DUT
  dut: entity work.REG
    port map (
      Clock      => Clock,
      Reset      => Reset,
      DataIn     => DataIn,
      Insert     => Insert,
      Delete     => Delete,
      Search     => Search,
      Count      => Count,
      Reverse    => Reverse,
      ShiftLeft  => ShiftLeft,
      ShiftRight => ShiftRight,
      Clear      => Clear,
      Get        => Get,
      Sort       => Sort,
      DataOut    => DataOut,
      Valid      => Valid
    );

  -- Clock generator
  clk_gen: process
  begin
    while done = '0' loop
      Clock <= '0';
      wait for CLK_PERIOD/2;
      Clock <= '1';
      wait for CLK_PERIOD/2;
    end loop;
    wait;
  end process;

  stim: process
    variable exp_regs   : reg_array_t := (others => (others => '0'));
    variable exp_valids : valid_vec_t := (others => '0');

    procedure pulse_one(signal s : out std_logic) is
    begin
      s <= '1';
      wait until rising_edge(Clock);
      s <= '0';
    end procedure;

    procedure do_insert(val : std_logic_vector(15 downto 0)) is
      variable idx : integer;
    begin
      DataIn <= val;
      Insert <= '1';
      wait until rising_edge(Clock);
      Insert <= '0';

      idx := first_invalid_index(exp_valids);
      if idx /= -1 then
        exp_regs(idx)   := val;
        exp_valids(idx) := '1';
      end if;

      -- Insert does not produce an output
      wait for 1 ns;
      assert Valid = '0'
        report "Insert: Valid should be 0" severity error;
    end procedure;

    procedure do_delete(val : std_logic_vector(15 downto 0)) is
      variable idx : integer;
    begin
      DataIn <= val;
      Delete <= '1';
      wait until rising_edge(Clock);
      Delete <= '0';

      idx := first_match_index(exp_regs, exp_valids, val);
      if idx /= -1 then
        exp_valids(idx) := '0';
        exp_regs(idx)   := (others => '0');
      end if;

      wait for 1 ns;
      assert Valid = '0'
        report "Delete: Valid should be 0" severity error;
    end procedure;

    procedure do_search(val : std_logic_vector(15 downto 0)) is
      variable idx : integer;
    begin
      DataIn <= val;
      Search <= '1';
      wait until rising_edge(Clock);
      Search <= '0';

      idx := first_match_index(exp_regs, exp_valids, val);

      wait for 1 ns;
      if idx = -1 then
        assert Valid = '0'
          report "Search(not found): Valid should be 0" severity error;
      else
        assert Valid = '1'
          report "Search(found): Valid should be 1" severity error;
        assert DataOut = std_logic_vector(to_unsigned(idx,16))
          report "Search(found): wrong index on DataOut" severity error;
      end if;
    end procedure;

    procedure do_count(val : std_logic_vector(15 downto 0)) is
      variable c : integer;
    begin
      DataIn <= val;
      Count <= '1';
      wait until rising_edge(Clock);
      Count <= '0';

      c := count_match(exp_regs, exp_valids, val);

      wait for 1 ns;
      assert Valid = '1'
        report "Count: Valid should be 1 (even if count=0)" severity error;
      assert DataOut = std_logic_vector(to_unsigned(c,16))
        report "Count: wrong count on DataOut" severity error;
    end procedure;

    procedure do_get(idx_int : integer) is
      variable idx_slv : std_logic_vector(15 downto 0);
    begin
      idx_slv := std_logic_vector(to_unsigned(idx_int,16));
      DataIn <= idx_slv;
      Get <= '1';
      wait until rising_edge(Clock);
      Get <= '0';

      wait for 1 ns;
      if (idx_int < 0) or (idx_int >= REG_DEPTH) then
        assert Valid = '0'
          report "Get(out of range): Valid should be 0" severity error;
      else
        if exp_valids(idx_int) = '1' then
          assert Valid = '1'
            report "Get(valid): Valid should be 1" severity error;
          assert DataOut = exp_regs(idx_int)
            report "Get(valid): wrong DataOut" severity error;
        else
          assert Valid = '0'
            report "Get(invalid slot): Valid should be 0" severity error;
        end if;
      end if;
    end procedure;

    procedure check_all_slots is
    begin
      for i in 0 to REG_DEPTH-1 loop
        do_get(i);
      end loop;
    end procedure;

    procedure do_reverse is
    begin
      Reverse <= '1';
      wait until rising_edge(Clock);
      Reverse <= '0';
      reverse_inplace(exp_regs, exp_valids);

      wait for 1 ns;
      assert Valid = '0'
        report "Reverse: Valid should be 0" severity error;
      check_all_slots;
    end procedure;

    procedure do_shift_left is
    begin
      ShiftLeft <= '1';
      wait until rising_edge(Clock);
      ShiftLeft <= '0';
      rotate_left_inplace(exp_regs, exp_valids);

      wait for 1 ns;
      assert Valid = '0'
        report "ShiftLeft: Valid should be 0" severity error;
      check_all_slots;
    end procedure;

    procedure do_shift_right is
    begin
      ShiftRight <= '1';
      wait until rising_edge(Clock);
      ShiftRight <= '0';
      rotate_right_inplace(exp_regs, exp_valids);

      wait for 1 ns;
      assert Valid = '0'
        report "ShiftRight: Valid should be 0" severity error;
      check_all_slots;
    end procedure;

    procedure do_sort is
    begin
      Sort <= '1';
      wait until rising_edge(Clock);
      Sort <= '0';
      sort_inplace(exp_regs, exp_valids);

      wait for 1 ns;
      assert Valid = '0'
        report "Sort: Valid should be 0" severity error;
      check_all_slots;
    end procedure;

    procedure do_clear is
    begin
      Clear <= '1';
      wait until rising_edge(Clock);
      Clear <= '0';
      exp_regs   := (others => (others => '0'));
      exp_valids := (others => '0');

      wait for 1 ns;
      assert Valid = '0'
        report "Clear: Valid should be 0" severity error;
      check_all_slots;
    end procedure;

    -- helper: wait N cycles
    procedure wait_cycles(n : natural) is
    begin
      for i in 1 to n loop
        wait until rising_edge(Clock);
      end loop;
    end procedure;

  begin
    -- init
    Insert     <= '0'; Delete <= '0'; Search <= '0'; Count <= '0';
    Reverse    <= '0'; ShiftLeft <= '0'; ShiftRight <= '0';
    Clear      <= '0'; Get <= '0'; Sort <= '0';
    DataIn     <= (others => '0');

    -- Asynchronous reset
    Reset <= '1';
    wait for 17 ns; -- not aligned with clock, to test async behavior
    Reset <= '0';
    wait_cycles(1);

    -- After reset everything must be invalid
    check_all_slots;

    -- Fill with some values (with duplicates)
    do_insert(x"0005"); -- idx0
    do_insert(x"000A"); -- idx1
    do_insert(x"0005"); -- idx2 (duplicate)
    do_insert(x"0001"); -- idx3
    do_insert(x"00FF"); -- idx4
    check_all_slots;

    -- Search tests
    do_search(x"0005"); -- expect found at idx0
    do_search(x"1234"); -- not found

    -- Count tests
    do_count(x"0005");  -- expect 2
    do_count(x"FFFF");  -- expect 0

    -- Delete first occurrence of 0x0005 (idx0 becomes invalid)
    do_delete(x"0005");
    check_all_slots;
    do_search(x"0005"); -- now should be found at idx2

    -- Insert should reuse first available space (idx0)
    do_insert(x"00AA"); -- goes to idx0
    check_all_slots;

    -- Reverse / rotate / sort (validate using Get sweep each time)
    do_reverse;
    do_shift_left;
    do_shift_right;

    -- Add more values to make sorting interesting and create some holes
    do_delete(x"000A");  -- delete an existing value
    do_insert(x"00F0");
    do_insert(x"0002");
    do_insert(x"0009");
    check_all_slots;

    do_sort;

    -- Clear synchronous
    do_clear;

    -- Asynchronous reset in the middle (again)
    do_insert(x"1111");
    do_insert(x"2222");
    wait_cycles(1);
    Reset <= '1';
    wait for 7 ns;
    Reset <= '0';
    wait_cycles(1);

    exp_regs   := (others => (others => '0'));
    exp_valids := (others => '0');
    check_all_slots;

    report "ALL TESTS PASSED" severity note;
    done <= '1';
    wait;
  end process;

end architecture;

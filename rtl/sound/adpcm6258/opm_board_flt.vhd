-- opm_board_flt.vhd
-- CZ-634C/644C (X68000) summing amplifier IC227: R246/R247 = 4.7k // C228/C229 = 1800p
-- -> first-order low-pass at ~18.8 kHz on the YM3012 path.
-- (The ADPCM path already applies the same pole inside adpcm_board_flt.)
-- Bilinear transform at 125 kHz (40 MHz / 320), Q16 coefficients, DC gain = 1.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity opm_board_flt is
port(
	clk	:in std_logic;		-- 40 MHz (sndclk)
	rstn	:in std_logic;
	dinL	:in std_logic_vector(15 downto 0);
	dinR	:in std_logic_vector(15 downto 0);
	doutL	:out std_logic_vector(15 downto 0);
	doutR	:out std_logic_vector(15 downto 0)
);
end opm_board_flt;

architecture rtl of opm_board_flt is
	constant DIV	:integer := 320;
	constant B0	:integer := 22172;	-- b0 = b1
	constant A1	:integer := 21192;	-- feedback (+a1 * y[n-1])
	signal cnt	:integer range 0 to DIV-1 := 0;
	signal xL1,xR1	:signed(15 downto 0) := (others=>'0');
	signal yL,yR	:signed(15 downto 0) := (others=>'0');

	function step(x, x1, y1 :signed(15 downto 0)) return signed is
		variable acc :signed(35 downto 0);
	begin
		acc := resize(x, 18) * to_signed(B0, 18)
		     + resize(x1, 18) * to_signed(B0, 18)
		     + resize(y1, 18) * to_signed(A1, 18);
		acc := acc + to_signed(32768, 36);	-- round
		if acc(35 downto 16) > 32767 then
			return to_signed(32767, 16);
		elsif acc(35 downto 16) < -32768 then
			return to_signed(-32768, 16);
		end if;
		return acc(31 downto 16);
	end function;
begin
	process(clk) begin
		if rising_edge(clk) then
			if rstn = '0' then
				cnt <= 0;
				xL1 <= (others=>'0'); xR1 <= (others=>'0');
				yL  <= (others=>'0'); yR  <= (others=>'0');
			elsif cnt = DIV-1 then
				cnt <= 0;
				yL  <= step(signed(dinL), xL1, yL);
				yR  <= step(signed(dinR), xR1, yR);
				xL1 <= signed(dinL);
				xR1 <= signed(dinR);
			else
				cnt <= cnt + 1;
			end if;
		end if;
	end process;
	doutL <= std_logic_vector(yL);
	doutR <= std_logic_vector(yR);
end rtl;
